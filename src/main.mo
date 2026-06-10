import Result "mo:base/Result";
import Text "mo:base/Text";
import Blob "mo:base/Blob";
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
// import Option "mo:base/Option";
import Int "mo:base/Int";
import Time "mo:base/Time";

import HttpTypes "mo:http-types";
import Map "mo:map/Map";

import AuthCleanup "mo:mcp-motoko-sdk/auth/Cleanup";
import AuthState "mo:mcp-motoko-sdk/auth/State";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";

import Mcp "mo:mcp-motoko-sdk/mcp/Mcp";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import HttpHandler "mo:mcp-motoko-sdk/mcp/HttpHandler";
import Cleanup "mo:mcp-motoko-sdk/mcp/Cleanup";
import State "mo:mcp-motoko-sdk/mcp/State";
import Payments "mo:mcp-motoko-sdk/mcp/Payments";
import HttpAssets "mo:mcp-motoko-sdk/mcp/HttpAssets";
import Beacon "mo:mcp-motoko-sdk/mcp/Beacon";
import ApiKey "mo:mcp-motoko-sdk/auth/ApiKey";

import IC "mo:ic";

import SrvTypes "mo:mcp-motoko-sdk/server/Types";

// Import tool modules
import ToolContext "tools/ToolContext";
import DebateCreate "tools/debate_create";
import DebateJoin "tools/debate_join";
import DebateStart "tools/debate_start";
import DebateSubmitArgument "tools/debate_submit_argument";
import DebateGetState "tools/debate_get_state";
import DebateVoteWinner "tools/debate_vote_winner";
import DebateListOpen "tools/debate_list_open";
import DebateGetLeaderboard "tools/debate_get_leaderboard";
import DebateFinalize "tools/debate_finalize";

// Import app state
import DebateState "State";

shared ({ caller = deployer }) persistent actor class McpServer() = self {

  // The canister owner
  var owner : Principal = deployer;

  // State for certified HTTP assets
  var stable_http_assets : HttpAssets.StableEntries = [];
  transient let http_assets = HttpAssets.init(stable_http_assets);

  // Resource contents (minimal for this server)
  var resourceContents = [
    ("file:///README.md", "# Debate Arena MCP Server\nA multiplayer debate platform for agents and users."),
  ];

  // The MCP application context
  var appContext : McpTypes.AppContext = State.init(resourceContents);

  // ── Debate Arena persistent state ──
  var debateState : DebateState.DebateState = DebateState.empty();

  // ═══════════════════════════════════════════════════════════════════
  // AUTHENTICATION — ENABLED (debate tools require auth for writes)
  // ═══════════════════════════════════════════════════════════════════

  let issuerUrl = "https://bfggx-7yaaa-aaaai-q32gq-cai.icp0.io";
  let allowanceUrl = "https://prometheusprotocol.org/connections";
  let requiredScopes = ["openid"];

  public query func transformJwksResponse({
    context = _context : Blob;
    response : IC.HttpRequestResult;
  }) : async IC.HttpRequestResult {
    { response with headers = [] };
  };

  let authContext : ?AuthTypes.AuthContext = ?AuthState.init(
    Principal.fromActor(self),
    owner,
    issuerUrl,
    requiredScopes,
    transformJwksResponse,
  );

  // ═══════════════════════════════════════════════════════════════════
  // BEACON — ENABLED
  // ═══════════════════════════════════════════════════════════════════

  let beaconCanisterId = Principal.fromText("m63pw-fqaaa-aaaai-q33pa-cai");
  transient let beaconContext : ?Beacon.BeaconContext = ?Beacon.init(
    beaconCanisterId,
    ?(15 * 60), // every 15 minutes
  );

  // --- Timers ---
  Cleanup.startCleanupTimer<system>(appContext);

  switch (authContext) {
    case (?ctx) { AuthCleanup.startCleanupTimer<system>(ctx) };
    case (null) { Debug.print("Authentication is disabled.") };
  };

  switch (beaconContext) {
    case (?ctx) { Beacon.startTimer<system>(ctx) };
    case (null) { Debug.print("Beacon is disabled.") };
  };

  // --- RESOURCES & TOOLS ---
  transient let resources : [McpTypes.Resource] = [
    {
      uri = "file:///README.md";
      name = "README.md";
      title = ?"Debate Arena Documentation";
      description = ?"Overview of the Debate Arena MCP server.";
      mimeType = ?"text/markdown";
    },
  ];

  // Create the tool context
  transient let toolContext : ToolContext.ToolContext = {
    canisterPrincipal = Principal.fromActor(self);
    owner = owner;
    appContext = appContext;
    state = debateState;
  };

  // Register all tools
  transient let tools : [McpTypes.Tool] = [
    DebateCreate.config(),
    DebateJoin.config(),
    DebateStart.config(),
    DebateSubmitArgument.config(),
    DebateGetState.config(),
    DebateVoteWinner.config(),
    DebateListOpen.config(),
    DebateGetLeaderboard.config(),
    DebateFinalize.config(),
  ];

  // --- CONFIGURE THE SDK ---
  transient let mcpConfig : McpTypes.McpConfig = {
    self = Principal.fromActor(self);
    allowanceUrl = ?allowanceUrl;
    serverInfo = {
      name = "debate-arena";
      title = "Debate Arena";
      version = "0.1.0";
    };
    resources = resources;
    resourceReader = func(uri) {
      Map.get(appContext.resourceContents, Map.thash, uri);
    };
    tools = tools;
    toolImplementations = [
      ("debate_create", DebateCreate.handle(toolContext)),
      ("debate_join", DebateJoin.handle(toolContext)),
      ("debate_start", DebateStart.handle(toolContext)),
      ("debate_submit_argument", DebateSubmitArgument.handle(toolContext)),
      ("debate_get_state", DebateGetState.handle(toolContext)),
      ("debate_vote_winner", DebateVoteWinner.handle(toolContext)),
      ("debate_list_open", DebateListOpen.handle(toolContext)),
      ("debate_get_leaderboard", DebateGetLeaderboard.handle(toolContext)),
      ("debate_finalize", DebateFinalize.handle(toolContext)),
    ];
    beacon = beaconContext;
  };

  // --- CREATE THE SERVER ---
  transient let mcpServer = Mcp.createServer(mcpConfig);

  // --- PUBLIC ENTRY POINTS ---

  public query func get_owner() : async Principal { return owner };

  public shared ({ caller }) func set_owner(new_owner : Principal) : async Result.Result<(), Payments.TreasuryError> {
    if (caller != owner) { return #err(#NotOwner) };
    owner := new_owner;
    return #ok(());
  };

  public shared func get_treasury_balance(ledger_id : Principal) : async Nat {
    return await Payments.get_treasury_balance(Principal.fromActor(self), ledger_id);
  };

  public shared ({ caller }) func withdraw(
    ledger_id : Principal,
    amount : Nat,
    destination : Payments.Destination,
  ) : async Result.Result<Nat, Payments.TreasuryError> {
    return await Payments.withdraw(caller, owner, ledger_id, amount, destination);
  };

  // HTTP handler context
  private func _create_http_context() : HttpHandler.Context {
    return {
      self = Principal.fromActor(self);
      active_streams = appContext.activeStreams;
      mcp_server = mcpServer;
      streaming_callback = http_request_streaming_callback;
      auth = authContext;
      http_asset_cache = ?http_assets.cache;
      mcp_path = ?"/mcp";
    };
  };

  public query func http_request(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    switch (HttpHandler.http_request(ctx, req)) {
      case (?mcpResponse) { return mcpResponse };
      case (null) {
        if (req.url == "/") {
          return {
            status_code = 200;
            headers = [("Content-Type", "text/html")];
            body = Text.encodeUtf8("<h1>⚔️ Debate Arena</h1><p>A multiplayer debate platform for agents and users.</p><p>Connect via MCP at <code>/mcp</code></p>");
            upgrade = null;
            streaming_strategy = null;
          };
        } else {
          return {
            status_code = 404;
            headers = [];
            body = Blob.fromArray([]);
            upgrade = null;
            streaming_strategy = null;
          };
        };
      };
    };
  };

  public shared func http_request_update(req : SrvTypes.HttpRequest) : async SrvTypes.HttpResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    let mcpResponse = await HttpHandler.http_request_update(ctx, req);
    switch (mcpResponse) {
      case (?res) { return res };
      case (null) {
        return {
          status_code = 404;
          headers = [];
          body = Blob.fromArray([]);
          upgrade = null;
          streaming_strategy = null;
        };
      };
    };
  };

  public query func http_request_streaming_callback(token : HttpTypes.StreamingToken) : async ?HttpTypes.StreamingCallbackResponse {
    let ctx : HttpHandler.Context = _create_http_context();
    return HttpHandler.http_request_streaming_callback(ctx, token);
  };

  // --- LIFECYCLE ---
  system func preupgrade() {
    stable_http_assets := HttpAssets.preupgrade(http_assets);
  };

  system func postupgrade() {
    HttpAssets.postupgrade(http_assets);
  };

  // --- API KEY MANAGEMENT ---
  public shared (msg) func create_my_api_key(name : Text, scopes : [Text]) : async Text {
    switch (authContext) {
      case (null) { Debug.trap("Authentication is not enabled.") };
      case (?ctx) { return await ApiKey.create_my_api_key(ctx, msg.caller, name, scopes) };
    };
  };

  public shared (msg) func revoke_my_api_key(key_id : Text) : async () {
    switch (authContext) {
      case (null) { Debug.trap("Authentication is not enabled.") };
      case (?ctx) { return ApiKey.revoke_my_api_key(ctx, msg.caller, key_id) };
    };
  };

  public query (msg) func list_my_api_keys() : async [AuthTypes.ApiKeyMetadata] {
    switch (authContext) {
      case (null) { Debug.trap("Authentication is not enabled.") };
      case (?ctx) { return ApiKey.list_my_api_keys(ctx, msg.caller) };
    };
  };

  public type UpgradeFinishedResult = {
    #InProgress : Nat;
    #Failed : (Nat, Text);
    #Success : Nat;
  };
  private func natNow() : Nat { return Int.abs(Time.now()) };
  public func icrc120_upgrade_finished() : async UpgradeFinishedResult {
    #Success(natNow());
  };
};
