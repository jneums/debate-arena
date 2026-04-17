import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Float "mo:base/Float";
import Nat "mo:base/Nat";

import ToolContext "ToolContext";
import Types "../Types";

module {

  public func config() : McpTypes.Tool = {
    name = "debate_get_leaderboard";
    title = ?"Get Leaderboard";
    description = ?"Get the debate leaderboard ranked by win rate. Public — no auth required.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("limit", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Max entries to return. Default: 20, Max: 100")),
        ])),
      ])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("entries", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([
            ("type", Json.str("object")),
            ("properties", Json.obj([
              ("principal", Json.obj([("type", Json.str("string"))])),
              ("debatesJoined", Json.obj([("type", Json.str("integer"))])),
              ("debatesWon", Json.obj([("type", Json.str("integer"))])),
              ("winRate", Json.obj([("type", Json.str("number"))])),
              ("rank", Json.obj([("type", Json.str("integer"))])),
            ])),
          ])),
        ])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : McpTypes.ToolFn {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let limit = switch (Result.toOption(Json.getAsNat(args, "limit"))) {
        case (?n) { if (n > 100) 100 else if (n == 0) 20 else n };
        case (null) { 20 };
      };

      let st = context.state;

      // Collect all leaderboard entries
      var entries : [(Text, Types.LeaderboardStats)] = [];
      for ((principal, stats) in Map.entries(st.leaderboard)) {
        entries := Array.append(entries, [(principal, stats)]);
      };

      // Sort by win rate descending, then by debatesWon descending
      entries := Array.sort<(Text, Types.LeaderboardStats)>(entries, func(a, b) {
        let winRateA = if (a.1.debatesJoined == 0) 0.0 else Float.fromInt(a.1.debatesWon) / Float.fromInt(a.1.debatesJoined);
        let winRateB = if (b.1.debatesJoined == 0) 0.0 else Float.fromInt(b.1.debatesWon) / Float.fromInt(b.1.debatesJoined);
        if (winRateA > winRateB) #less
        else if (winRateA < winRateB) #greater
        else Nat.compare(b.1.debatesWon, a.1.debatesWon);
      });

      // Take top `limit`
      let total = entries.size();
      let take = if (total < limit) total else limit;

      var resultJson : [Json.Json] = [];
      var rank : Nat = 1;
      for (i in Array.keys(entries)) {
        if (rank > take) {
          // done
        } else {
          let (principal, stats) = entries[i];
          let winRate = if (stats.debatesJoined == 0) 0.0 else Float.fromInt(stats.debatesWon) / Float.fromInt(stats.debatesJoined);
          let winRatePct = Float.nearest(winRate * 10000.0) / 100.0; // e.g. 66.67

          resultJson := Array.append(resultJson, [Json.obj([
            ("principal", Json.str(principal)),
            ("debatesJoined", Json.int(stats.debatesJoined)),
            ("debatesWon", Json.int(stats.debatesWon)),
            ("winRate", Json.float(winRatePct)),
            ("rank", Json.int(rank)),
          ])]);
          rank += 1;
        };
      };

      let payload = Json.obj([
        ("entries", Json.arr(resultJson)),
        ("totalEntries", Json.int(total)),
      ]);

      ToolContext.makeSuccess(payload, cb);
    };
  };
};
