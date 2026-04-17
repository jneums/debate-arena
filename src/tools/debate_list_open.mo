import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Int "mo:base/Int";

import ToolContext "ToolContext";
import Types "../Types";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_list_open";
    title = ?"List Open Debates";
    description = ?"List debates that are currently open for joining, in progress, or in voting. Public — no auth required.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("limit", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Max results to return. Default: 20, Max: 100")),
        ])),
        ("status", Json.obj([
          ("type", Json.str("string")),
          ("enum", Json.arr([
            Json.str("open_for_join"),
            Json.str("opening_round"),
            Json.str("rebuttal_round"),
            Json.str("closing_round"),
            Json.str("voting"),
            Json.str("completed"),
            Json.str("all"),
          ])),
          ("description", Json.str("Filter by status. Default: all active (non-completed, non-cancelled)")),
        ])),
      ])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debates", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("object"))])),
        ])),
        ("totalMatched", Json.obj([("type", Json.str("integer"))])),
      ])),
    ]);
  };

  func isActive(status : Types.DebateStatus) : Bool {
    switch (status) {
      case (#completed or #cancelled) false;
      case (_) true;
    };
  };

  func statusMatches(status : Types.DebateStatus, filter : Text) : Bool {
    if (filter == "all") return true;
    return Types.statusToText(status) == filter;
  };

  public func handle(context : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let limit = switch (Result.toOption(Json.getAsNat(args, "limit"))) {
        case (?n) { if (n > 100) 100 else if (n == 0) 20 else n };
        case (null) { 20 };
      };

      let statusFilter = switch (Result.toOption(Json.getAsText(args, "status"))) {
        case (?s) { s };
        case (null) { "active" }; // default: all active
      };

      let st = context.state;

      var results : [Json.Json] = [];
      var count : Nat = 0;

      for ((_, debate) in Map.entries(st.debates)) {
        if (count >= limit) {
          // break - Motoko doesn't have break in for, so we just skip
        } else {
          let matches = if (statusFilter == "active") {
            isActive(debate.status);
          } else {
            statusMatches(debate.status, statusFilter);
          };

          if (matches) {
            results := Array.append(results, [Json.obj([
              ("debateId", Json.str(debate.debateId)),
              ("topic", Json.str(debate.topic)),
              ("format", Json.str(Types.formatToText(debate.format))),
              ("status", Json.str(Types.statusToText(debate.status))),
              ("createdBy", Json.str(debate.createdBy)),
              ("createdAt", Json.int(Int.abs(debate.createdAt))),
              ("sides", Json.arr(Array.map<Text, Json.Json>(debate.sides, func(s) { Json.str(s) }))),
              ("currentRound", Json.int(debate.currentRound)),
            ])]);
            count += 1;
          };
        };
      };

      let payload = Json.obj([
        ("debates", Json.arr(results)),
        ("totalMatched", Json.int(count)),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
