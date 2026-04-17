import Principal "mo:base/Principal";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Time "mo:base/Time";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Option "mo:base/Option";

import ToolContext "ToolContext";
import Types "../Types";
import State "../State";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_join";
    title = ?"Join Debate";
    description = ?"Join an open debate on a specific side. Requires authentication.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate to join")),
        ])),
        ("side", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("Which side to join (must match one of the debate's sides)")),
        ])),
      ])),
      ("required", Json.arr([Json.str("debateId"), Json.str("side")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([("type", Json.str("string"))])),
        ("side", Json.obj([("type", Json.str("string"))])),
        ("joined", Json.obj([("type", Json.str("boolean"))])),
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

      let side = switch (Result.toOption(Json.getAsText(args, "side"))) {
        case (?s) { s };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'side'.", cb) };
      };

      let st = context.state;

      // Look up debate
      let debate = switch (Map.get(st.debates, Map.thash, debateId)) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("NOT_FOUND: Debate '" # debateId # "' not found.", cb) };
      };

      // Must be open_for_join
      switch (debate.status) {
        case (#open_for_join) {};
        case (_) { return ToolContext.makeError("INVALID_STATE: Debate is not open for joining. Status: " # Types.statusToText(debate.status), cb) };
      };

      // Validate side
      let validSide = Array.find<Text>(debate.sides, func(s) { s == side });
      if (Option.isNull(validSide)) {
        return ToolContext.makeError("INVALID_INPUT: Side '" # side # "' is not one of the debate's sides.", cb);
      };

      // Check not already joined
      let pKey = State.participantKey(debateId, caller);
      switch (Map.get(st.participants, Map.thash, pKey)) {
        case (?_) { return ToolContext.makeError("ALREADY_JOINED: You have already joined this debate.", cb) };
        case (null) {};
      };

      // Check max participants per side
      let currentParticipants = Option.get(Map.get(st.participantsByDebate, Map.thash, debateId), [] : [Text]);
      var sideCount : Nat = 0;
      for (p in currentParticipants.vals()) {
        let pk = State.participantKey(debateId, p);
        switch (Map.get(st.participants, Map.thash, pk)) {
          case (?part) { if (part.side == side) { sideCount += 1 } };
          case (null) {};
        };
      };
      if (sideCount >= debate.maxParticipantsPerSide) {
        return ToolContext.makeError("INVALID_STATE: Side '" # side # "' is full (" # debug_show(debate.maxParticipantsPerSide) # " max).", cb);
      };

      // Add participant
      let participant : Types.Participant = {
        principal = caller;
        displayName = null;
        side;
        joinedAt = Time.now();
      };
      Map.set(st.participants, Map.thash, pKey, participant);
      let updated = Array.append(currentParticipants, [caller]);
      Map.set(st.participantsByDebate, Map.thash, debateId, updated);

      let payload = Json.obj([
        ("debateId", Json.str(debateId)),
        ("side", Json.str(side)),
        ("joined", Json.bool(true)),
        ("participantCount", Json.int(updated.size())),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
