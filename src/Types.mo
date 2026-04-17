import Text "mo:base/Text";
import Nat "mo:base/Nat";

module {

  // ── Debate status state machine ──
  // open_for_join → opening_round → rebuttal_round → closing_round → voting → completed
  //                                                                          → cancelled (from any state by creator)
  public type DebateStatus = {
    #open_for_join;
    #opening_round;
    #rebuttal_round;
    #closing_round;
    #voting;
    #completed;
    #cancelled;
  };

  public type DebateFormat = {
    #oneVone;
    #team;
    #open;
  };

  public type Debate = {
    debateId : Text;
    topic : Text;
    format : DebateFormat;
    status : DebateStatus;
    createdBy : Text; // principal as text
    createdAt : Int;  // Time.now() nanos
    sides : [Text];
    currentRound : Nat;
    maxParticipantsPerSide : Nat;
  };

  public type Participant = {
    principal : Text;
    displayName : ?Text;
    side : Text;
    joinedAt : Int;
  };

  public type ArgumentRecord = {
    argumentId : Text;
    debateId : Text;
    principal : Text;
    side : Text;
    roundNumber : Nat;
    contentText : Text;
    submittedAt : Int;
  };

  public type Vote = {
    voter : Text;
    debateId : Text;
    winnerSide : Text;
    castAt : Int;
  };

  public type LeaderboardEntry = {
    principal : Text;
    debatesJoined : Nat;
    debatesWon : Nat;
    winRate : Float;
    rank : Nat;
  };

  public type LeaderboardStats = {
    debatesJoined : Nat;
    debatesWon : Nat;
  };

  // ── Helper: status to text ──
  public func statusToText(s : DebateStatus) : Text {
    switch (s) {
      case (#open_for_join) "open_for_join";
      case (#opening_round) "opening_round";
      case (#rebuttal_round) "rebuttal_round";
      case (#closing_round) "closing_round";
      case (#voting) "voting";
      case (#completed) "completed";
      case (#cancelled) "cancelled";
    };
  };

  public func formatToText(f : DebateFormat) : Text {
    switch (f) {
      case (#oneVone) "1v1";
      case (#team) "team";
      case (#open) "open";
    };
  };

  public func textToFormat(t : Text) : DebateFormat {
    switch (t) {
      case ("1v1") #oneVone;
      case ("team") #team;
      case ("open") #open;
      case (_) #oneVone; // default
    };
  };

  // ── Phase for a given round number ──
  public func roundPhase(round : Nat) : Text {
    switch (round) {
      case (1) "opening";
      case (2) "rebuttal";
      case (3) "closing";
      case (_) "extra";
    };
  };
};
