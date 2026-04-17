import Principal "mo:base/Principal";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Option "mo:base/Option";

import ToolContext "ToolContext";
import Types "../Types";
import State "../State";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_finalize";
    title = ?"Finalize Debate";
    description = ?"Close voting and finalize the debate. Tallies votes, determines winner, and updates the leaderboard. Only the debate creator can finalize. Requires authentication.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate to finalize")),
        ])),
      ])),
      ("required", Json.arr([Json.str("debateId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("status", Json.obj([("type", Json.str("string"))])),
        ("winningSide", Json.obj([("type", Json.str("string"))])),
        ("isTie", Json.obj([("type", Json.str("boolean"))])),
        ("voteSummary", Json.obj([("type", Json.str("array")), ("items", Json.obj([("type", Json.str("object"))]))])),
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

      // Only creator can finalize
      if (caller != debate.createdBy) {
        return ToolContext.makeError("UNAUTHORIZED: Only the debate creator can finalize.", cb);
      };

      // Must be in voting phase
      switch (debate.status) {
        case (#voting) {};
        case (_) { return ToolContext.makeError("INVALID_STATE: Debate is not in voting phase. Status: " # Types.statusToText(debate.status), cb) };
      };

      // Tally votes
      let voters = Option.get(Map.get(st.votesByDebate, Map.thash, debateId), [] : [Text]);
      var voteCounts = Map.new<Text, Nat>();
      for (v in voters.vals()) {
        let vKey = State.voteKey(debateId, v);
        switch (Map.get(st.votes, Map.thash, vKey)) {
          case (?vote) {
            let current = Option.get(Map.get(voteCounts, Map.thash, vote.winnerSide), 0);
            Map.set(voteCounts, Map.thash, vote.winnerSide, current + 1);
          };
          case (null) {};
        };
      };

      // Find winner
      var maxVotes : Nat = 0;
      var winningSide : Text = "";
      var isTie = false;

      for (side in debate.sides.vals()) {
        let count = Option.get(Map.get(voteCounts, Map.thash, side), 0);
        if (count > maxVotes) {
          maxVotes := count;
          winningSide := side;
          isTie := false;
        } else if (count == maxVotes and count > 0) {
          isTie := true;
        };
      };

      // Update debate status
      let updated : Types.Debate = {
        debate with status = #completed;
      };
      Map.set(st.debates, Map.thash, debateId, updated);

      // Update leaderboard for all participants
      let participants = Option.get(Map.get(st.participantsByDebate, Map.thash, debateId), [] : [Text]);
      for (p in participants.vals()) {
        let pKey = State.participantKey(debateId, p);
        let partOpt = Map.get(st.participants, Map.thash, pKey);
        let existing = Option.get(Map.get(st.leaderboard, Map.thash, p), { debatesJoined = 0; debatesWon = 0 } : Types.LeaderboardStats);

        let won = switch (partOpt) {
          case (?part) { not isTie and part.side == winningSide };
          case (null) { false };
        };

        let updatedStats : Types.LeaderboardStats = {
          debatesJoined = existing.debatesJoined + 1;
          debatesWon = if (won) existing.debatesWon + 1 else existing.debatesWon;
        };
        Map.set(st.leaderboard, Map.thash, p, updatedStats);
      };

      // Build vote summary
      let voteSummaryJson = Array.map<Text, Json.Json>(debate.sides, func(side) {
        let count = Option.get(Map.get(voteCounts, Map.thash, side), 0);
        Json.obj([
          ("side", Json.str(side)),
          ("votes", Json.int(count)),
        ]);
      });

      let payload = Json.obj([
        ("status", Json.str("completed")),
        ("winningSide", Json.str(if (isTie) "TIE" else winningSide)),
        ("isTie", Json.bool(isTie)),
        ("totalVotes", Json.int(voters.size())),
        ("voteSummary", Json.arr(voteSummaryJson)),
        ("leaderboardUpdated", Json.bool(true)),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
