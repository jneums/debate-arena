import Principal "mo:base/Principal";
import Result "mo:base/Result";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import Json "mo:json";

import State "../State";

module ToolContext {

  /// Context shared between tools and the main canister
  public type ToolContext = {
    canisterPrincipal : Principal;
    owner : Principal;
    appContext : McpTypes.AppContext;
    state : State.DebateState;
  };

  /// Helper: error response
  public func makeError(message : Text, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = "Error: " # message })]; isError = true; structuredContent = null }));
  };

  /// Helper: success with structured JSON
  public func makeSuccess(structured : Json.Json, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = Json.stringify(structured, null) })]; isError = false; structuredContent = ?structured }));
  };

  /// Helper: success with plain text
  public func makeTextSuccess(text : Text, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = text })]; isError = false; structuredContent = null }));
  };
};
