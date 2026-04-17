import Map "mo:map/Map";
import Types "Types";

module {

  public type DebateState = {
    // debates by debateId
    debates : Map.Map<Text, Types.Debate>;
    // participants: key = debateId#principal
    participants : Map.Map<Text, Types.Participant>;
    // participantsByDebate: debateId -> [principal]
    participantsByDebate : Map.Map<Text, [Text]>;
    // arguments: key = argumentId
    arguments : Map.Map<Text, Types.ArgumentRecord>;
    // argumentsByDebate: debateId -> [argumentId]
    argumentsByDebate : Map.Map<Text, [Text]>;
    // votes: key = debateId#voter
    votes : Map.Map<Text, Types.Vote>;
    // votesByDebate: debateId -> [voter]
    votesByDebate : Map.Map<Text, [Text]>;
    // leaderboard stats by principal
    leaderboard : Map.Map<Text, Types.LeaderboardStats>;
    // auto-increment counter for IDs
    var nextId : Nat;
  };

  public func empty() : DebateState {
    {
      debates = Map.new<Text, Types.Debate>();
      participants = Map.new<Text, Types.Participant>();
      participantsByDebate = Map.new<Text, [Text]>();
      arguments = Map.new<Text, Types.ArgumentRecord>();
      argumentsByDebate = Map.new<Text, [Text]>();
      votes = Map.new<Text, Types.Vote>();
      votesByDebate = Map.new<Text, [Text]>();
      leaderboard = Map.new<Text, Types.LeaderboardStats>();
      var nextId = 1;
    };
  };

  // Composite key helpers
  public func participantKey(debateId : Text, principal : Text) : Text {
    debateId # "#" # principal;
  };

  public func voteKey(debateId : Text, voter : Text) : Text {
    debateId # "#" # voter;
  };

  public func genId(state : DebateState, prefix : Text) : Text {
    let id = prefix # "-" # debug_show(state.nextId);
    state.nextId += 1;
    id;
  };
};
