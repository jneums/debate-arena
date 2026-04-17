import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Option "mo:base/Option";
import Int "mo:base/Int";

import ToolContext "ToolContext";
import Types "../Types";
import State "../State";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_get_state";
    title = ?"Get Debate State";
    description = ?"Get the full state of a debate including participants, arguments, and vote summary. Public — no auth required.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debateId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The debate ID to inspect")),
        ])),
      ])),
      ("required", Json.arr([Json.str("debateId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("debate", Json.obj([("type", Json.str("object"))])),
        ("participants", Json.obj([("type", Json.str("array")), ("items", Json.obj([("type", Json.str("object"))]))])),
        ("arguments", Json.obj([("type", Json.str("array")), ("items", Json.obj([("type", Json.str("object"))]))])),
        ("voteSummary", Json.obj([("type", Json.str("array")), ("items", Json.obj([("type", Json.str("object"))]))])),
      ])),
    ]);
  };

  func formatTimestamp(nanos : Int) : Json.Json {
    Json.int(Int.abs(nanos));
  };

  public func handle(context : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let debateId = switch (Result.toOption(Json.getAsText(args, "debateId"))) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("INVALID_INPUT: Missing 'debateId'.", cb) };
      };

      let st = context.state;

      let debate = switch (Map.get(st.debates, Map.thash, debateId)) {
        case (?d) { d };
        case (null) { return ToolContext.makeError("NOT_FOUND: Debate not found.", cb) };
      };

      // Build debate JSON
      let debateJson = Json.obj([
        ("debateId", Json.str(debate.debateId)),
        ("topic", Json.str(debate.topic)),
        ("format", Json.str(Types.formatToText(debate.format))),
        ("status", Json.str(Types.statusToText(debate.status))),
        ("createdBy", Json.str(debate.createdBy)),
        ("createdAt", formatTimestamp(debate.createdAt)),
        ("sides", Json.arr(Array.map<Text, Json.Json>(debate.sides, func(s) { Json.str(s) }))),
        ("currentRound", Json.int(debate.currentRound)),
        ("maxParticipantsPerSide", Json.int(debate.maxParticipantsPerSide)),
      ]);

      // Build participants array
      let participantPrincipals = Option.get(Map.get(st.participantsByDebate, Map.thash, debateId), [] : [Text]);
      let participantsJson = Array.map<Text, Json.Json>(participantPrincipals, func(p) {
        let pKey = State.participantKey(debateId, p);
        switch (Map.get(st.participants, Map.thash, pKey)) {
          case (?part) {
            Json.obj([
              ("principal", Json.str(part.principal)),
              ("side", Json.str(part.side)),
              ("joinedAt", formatTimestamp(part.joinedAt)),
            ]);
          };
          case (null) { Json.obj([("principal", Json.str(p))]) };
        };
      });

      // Build arguments array
      let argIds = Option.get(Map.get(st.argumentsByDebate, Map.thash, debateId), [] : [Text]);
      var argsList : [Json.Json] = [];
      for (aid in argIds.vals()) {
        switch (Map.get(st.arguments, Map.thash, aid)) {
          case (?a) {
            argsList := Array.append(argsList, [Json.obj([
              ("argumentId", Json.str(a.argumentId)),
              ("principal", Json.str(a.principal)),
              ("side", Json.str(a.side)),
              ("roundNumber", Json.int(a.roundNumber)),
              ("phase", Json.str(Types.roundPhase(a.roundNumber))),
              ("contentText", Json.str(a.contentText)),
              ("submittedAt", formatTimestamp(a.submittedAt)),
            ])]);
          };
          case (null) {};
        };
      };

      // Build vote summary
      let voters = Option.get(Map.get(st.votesByDebate, Map.thash, debateId), [] : [Text]);
      // Count votes per side
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
      let voteSummaryJson = Array.map<Text, Json.Json>(debate.sides, func(side) {
        let count = Option.get(Map.get(voteCounts, Map.thash, side), 0);
        Json.obj([
          ("side", Json.str(side)),
          ("votes", Json.int(count)),
        ]);
      });

      // Build rounds info
      let roundsJson = Json.arr([
        Json.obj([("roundNumber", Json.int(1)), ("phase", Json.str("opening"))]),
        Json.obj([("roundNumber", Json.int(2)), ("phase", Json.str("rebuttal"))]),
        Json.obj([("roundNumber", Json.int(3)), ("phase", Json.str("closing"))]),
      ]);

      let payload = Json.obj([
        ("debate", debateJson),
        ("rounds", roundsJson),
        ("participants", Json.arr(participantsJson)),
        ("arguments", Json.arr(argsList)),
        ("voteSummary", Json.arr(voteSummaryJson)),
        ("totalVotes", Json.int(voters.size())),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
