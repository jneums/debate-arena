import Principal "mo:base/Principal";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Map "mo:map/Map";
import Option "mo:base/Option";

import ToolContext "ToolContext";
import Types "../Types";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_start";
    title = ?"Start Debate";
    description = ?"Move a debate from 'open_for_join' to 'opening_round'. Only the debate creator can start it. Requires at least one participant on each side. Requires authentication.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate to start")),
        ])),
      ])),
      ("required", Json.arr([Json.str("debateId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("currentRound", Json.obj([("type", Json.str("integer"))])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let callerPrincipal = switch (auth) {
        case (?a) { a.principal };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: Authentication required.", cb) };
      };
      let caller = Principal.toText(callerPrincipal);

      let debateId = switch (Result.toOption(Json.getAsText(args, "debateId"))) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'debateId'.", cb) };
      };

      let st = context.state;

      let debate = switch (Map.get(st.debates, Map.thash, debateId)) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("NOT_FOUND: Debate not found.", cb) };
      };

      // Only creator can start
      if (caller != debate.createdBy) {
        return ToolContext.makeError("UNAUTHORIZED: Only the debate creator can start it.", cb);
      };

      // Must be open_for_join
      switch (debate.status) {
        case (#open_for_join) {};
        case (_) { return ToolContext.makeError("INVALID_STATE: Debate is not in 'open_for_join' status. Current: " # Types.statusToText(debate.status), cb) };
      };

      // Check that each side has at least one participant
      let participants = Option.get(Map.get(st.participantsByDebate, Map.thash, debateId), [] : [Text]);
      for (side in debate.sides.vals()) {
        var found = false;
        for (p in participants.vals()) {
          let pKey = debateId # "#" # p;
          switch (Map.get(st.participants, Map.thash, pKey)) {
            case (?part) { if (part.side == side) { found := true } };
            case (null) {};
          };
        };
        if (not found) {
          return ToolContext.makeError("INVALID_STATE: Side '" # side # "' has no participants. Each side needs at least one.", cb);
        };
      };

      // Advance to opening_round
      let updated : Types.Debate = {
        debate with
        status = #opening_round;
        currentRound = 1;
      };
      Map.set(st.debates, Map.thash, debateId, updated);

      let payload = Json.obj([
        ("debateId", Json.str(debateId)),
        ("status", Json.str("opening_round")),
        ("currentRound", Json.int(1)),
        ("phase", Json.str("opening")),
        ("message", Json.str("Debate started! Participants can now submit opening arguments.")),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
