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
    name = "debate_vote_winner";
    title = ?"Vote Winner";
    description = ?"Cast your vote for the winning side of a debate in voting phase. Requires authentication. Participants in the debate cannot vote.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate to vote on")),
        ])),
        ("winnerSide", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The side you think won the debate")),
        ])),
      ])),
      ("required", Json.arr([Json.str("debateId"), Json.str("winnerSide")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("status", Json.obj([("type", Json.str("string"))])),
        ("voteAccepted", Json.obj([("type", Json.str("boolean"))])),
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

      let winnerSide = switch (Result.toOption(Json.getAsText(args, "winnerSide"))) {
        case (?s) { s };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'winnerSide'.", cb) };
      };

      let st = context.state;

      let debate = switch (Map.get(st.debates, Map.thash, debateId)) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("NOT_FOUND: Debate not found.", cb) };
      };

      // Must be in voting phase
      switch (debate.status) {
        case (#voting) {};
        case (_) { return ToolContext.makeError("INVALID_STATE: Debate is not in voting phase. Status: " # Types.statusToText(debate.status), cb) };
      };

      // Validate side
      let validSide = Array.find<Text>(debate.sides, func(s) { s == winnerSide });
      if (Option.isNull(validSide)) {
        return ToolContext.makeError("INVALID_INPUT: '" # winnerSide # "' is not a valid side.", cb);
      };

      // Participants cannot vote in their own debate
      let pKey = State.participantKey(debateId, caller);
      switch (Map.get(st.participants, Map.thash, pKey)) {
        case (?_) { return ToolContext.makeError("UNAUTHORIZED: Participants cannot vote in their own debate.", cb) };
        case (null) {};
      };

      // Check for duplicate vote
      let vKey = State.voteKey(debateId, caller);
      switch (Map.get(st.votes, Map.thash, vKey)) {
        case (?_) { return ToolContext.makeError("DUPLICATE_VOTE: You have already voted in this debate.", cb) };
        case (null) {};
      };

      // Record vote
      let vote : Types.Vote = {
        voter = caller;
        debateId;
        winnerSide;
        castAt = Time.now();
      };
      Map.set(st.votes, Map.thash, vKey, vote);
      let existingVoters = Option.get(Map.get(st.votesByDebate, Map.thash, debateId), [] : [Text]);
      Map.set(st.votesByDebate, Map.thash, debateId, Array.append(existingVoters, [caller]));

      let payload = Json.obj([
        ("status", Json.str("vote_recorded")),
        ("voteAccepted", Json.bool(true)),
        ("winnerSide", Json.str(winnerSide)),
        ("totalVotes", Json.int(existingVoters.size() + 1)),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
