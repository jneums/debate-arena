import Principal "mo:base/Principal";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Time "mo:base/Time";
import Map "mo:map/Map";
import Array "mo:base/Array";

import ToolContext "ToolContext";
import Types "../Types";
import State "../State";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_create";
    title = ?"Create Debate";
    description = ?"Create a new debate topic with named sides. Requires authentication.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("topic", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate topic or question")),
        ])),
        ("sides", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("string"))])),
          ("minItems", Json.int(2)),
          ("maxItems", Json.int(10)),
          ("description", Json.str("Named sides/positions (e.g. [\"For\", \"Against\"])")),
        ])),
        ("format", Json.obj([
          ("type", Json.str("string")),
          ("enum", Json.arr([Json.str("1v1"), Json.str("team"), Json.str("open")])),
          ("description", Json.str("Debate format. Default: 1v1")),
        ])),
        ("maxParticipantsPerSide", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Max participants per side. Default: 1 for 1v1, 5 for team/open")),
        ])),
      ])),
      ("required", Json.arr([Json.str("topic"), Json.str("sides")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("topic", Json.obj([("type", Json.str("string"))])),
        ("sides", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("string"))])),
        ])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      // Require auth
      let callerPrincipal = switch (auth) {
        case (?a) { a.principal };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: Authentication required to create a debate.", cb) };
      };
      let caller = Principal.toText(callerPrincipal);

      // Parse topic
      let topic = switch (Result.toOption(Json.getAsText(args, "topic"))) {
        case (?t) { t };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'topic'.", cb) };
      };

      // Parse sides array
      let sidesJson = switch (Json.get(args, "sides")) {
        case (?s) { s };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'sides' array.", cb) };
      };
      let sidesArr = switch (sidesJson) {
        case (#array(arr)) { arr };
        case (_) { return ToolContext.makeError("INVALID_INPUT: 'sides' must be an array.", cb) };
      };
      if (sidesArr.size() < 2) {
        return ToolContext.makeError("INVALID_INPUT: Need at least 2 sides.", cb);
      };
      let sides = Array.map<Json.Json, Text>(sidesArr, func(j) { 
        switch (j) { case (#string(t)) t; case (_) "" };
      });

      // Parse optional format
      let formatText = switch (Result.toOption(Json.getAsText(args, "format"))) {
        case (?f) { f };
        case (null) { "1v1" };
      };
      let format = Types.textToFormat(formatText);

      // Parse optional maxParticipantsPerSide
      let maxPPS = switch (Result.toOption(Json.getAsNat(args, "maxParticipantsPerSide"))) {
        case (?n) { n };
        case (null) {
          switch (format) {
            case (#oneVone) 1;
            case (_) 5;
          };
        };
      };

      // Create the debate
      let st = context.state;
      let debateId = State.genId(st, "debate");
      let now = Time.now();

      let debate : Types.Debate = {
        debateId;
        topic;
        format;
        status = #open_for_join;
        createdBy = caller;
        createdAt = now;
        sides;
        currentRound = 0;
        maxParticipantsPerSide = maxPPS;
      };

      Map.set(st.debates, Map.thash, debateId, debate);
      Map.set(st.participantsByDebate, Map.thash, debateId, []);
      Map.set(st.argumentsByDebate, Map.thash, debateId, []);
      Map.set(st.votesByDebate, Map.thash, debateId, []);

      let payload = Json.obj([
        ("debateId", Json.str(debateId)),
        ("status", Json.str("open_for_join")),
        ("topic", Json.str(topic)),
        ("sides", Json.arr(Array.map<Text, Json.Json>(sides, func(s) { Json.str(s) }))),
        ("format", Json.str(Types.formatToText(format))),
        ("maxParticipantsPerSide", Json.int(maxPPS)),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
