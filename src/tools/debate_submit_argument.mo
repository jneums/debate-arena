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
    name = "debate_submit_argument";
    title = ?"Submit Argument";
    description = ?"Submit an argument for the current round of a debate. Requires authentication. You must be a participant.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate ID")),
        ])),
        ("contentText", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("Your argument text")),
        ])),
      ])),
      ("required", Json.arr([Json.str("debateId"), Json.str("contentText")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("argumentId", Json.obj([("type", Json.str("string"))])),
        ("status", Json.obj([("type", Json.str("string"))])),
        ("roundNumber", Json.obj([("type", Json.str("integer"))])),
        ("phase", Json.obj([("type", Json.str("string"))])),
      ])),
    ]);
  };

  // Check if the debate status allows argument submission
  func isArgumentPhase(status : Types.DebateStatus) : Bool {
    switch (status) {
      case (#opening_round or #rebuttal_round or #closing_round) true;
      case (_) false;
    };
  };

  func statusToRound(status : Types.DebateStatus) : Nat {
    switch (status) {
      case (#opening_round) 1;
      case (#rebuttal_round) 2;
      case (#closing_round) 3;
      case (_) 0;
    };
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

      let contentText = switch (Result.toOption(Json.getAsText(args, "contentText"))) {
        case (?c) { c };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'contentText'.", cb) };
      };

      let st = context.state;

      // Look up debate
      let debate = switch (Map.get(st.debates, Map.thash, debateId)) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("NOT_FOUND: Debate not found.", cb) };
      };

      // Check debate is in an argument phase
      if (not isArgumentPhase(debate.status)) {
        return ToolContext.makeError("INVALID_STATE: Debate is not accepting arguments. Status: " # Types.statusToText(debate.status) # ". Use debate_advance_round or wait for the debate to be in an argument phase.", cb);
      };

      // Check caller is a participant
      let pKey = State.participantKey(debateId, caller);
      let participant = switch (Map.get(st.participants, Map.thash, pKey)) {
        case (?p) { p };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: You are not a participant in this debate.", cb) };
      };

      let roundNumber = statusToRound(debate.status);

      // Check if caller already submitted for this round
      let existingArgIds = Option.get(Map.get(st.argumentsByDebate, Map.thash, debateId), [] : [Text]);
      for (aid in existingArgIds.vals()) {
        switch (Map.get(st.arguments, Map.thash, aid)) {
          case (?existing) {
            if (existing.principal == caller and existing.roundNumber == roundNumber) {
              return ToolContext.makeError("INVALID_STATE: You already submitted an argument for round " # debug_show(roundNumber) # ".", cb);
            };
          };
          case (null) {};
        };
      };

      // Create argument
      let argumentId = State.genId(st, "arg");
      let arg : Types.ArgumentRecord = {
        argumentId;
        debateId;
        principal = caller;
        side = participant.side;
        roundNumber;
        contentText;
        submittedAt = Time.now();
      };

      Map.set(st.arguments, Map.thash, argumentId, arg);
      let updatedArgIds = Array.append(existingArgIds, [argumentId]);
      Map.set(st.argumentsByDebate, Map.thash, debateId, updatedArgIds);

      // Check if all participants have submitted for this round → auto-advance
      let participants = Option.get(Map.get(st.participantsByDebate, Map.thash, debateId), [] : [Text]);
      var allSubmitted = true;
      label checkLoop for (p in participants.vals()) {
        var found = false;
        for (aid in updatedArgIds.vals()) {
          switch (Map.get(st.arguments, Map.thash, aid)) {
            case (?a) { if (a.principal == p and a.roundNumber == roundNumber) { found := true } };
            case (null) {};
          };
        };
        if (not found) { allSubmitted := false; break checkLoop };
      };

      // Auto-advance to next phase if all submitted
      if (allSubmitted) {
        let nextStatus : Types.DebateStatus = switch (debate.status) {
          case (#opening_round) #rebuttal_round;
          case (#rebuttal_round) #closing_round;
          case (#closing_round) #voting;
          case (other) other;
        };
        let nextRound = switch (nextStatus) {
          case (#rebuttal_round) 2;
          case (#closing_round) 3;
          case (_) debate.currentRound;
        };
        let updated : Types.Debate = {
          debate with
          status = nextStatus;
          currentRound = nextRound;
        };
        Map.set(st.debates, Map.thash, debateId, updated);
      };

      let phase = Types.roundPhase(roundNumber);
      let payload = Json.obj([
        ("argumentId", Json.str(argumentId)),
        ("status", Json.str("submitted")),
        ("roundNumber", Json.int(roundNumber)),
        ("phase", Json.str(phase)),
        ("autoAdvanced", Json.bool(allSubmitted)),
        ("debateStatus", Json.str(Types.statusToText(
          if (allSubmitted) {
            switch (debate.status) {
              case (#opening_round) #rebuttal_round;
              case (#rebuttal_round) #closing_round;
              case (#closing_round) #voting;
              case (other) other;
            };
          } else { debate.status }
        ))),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
