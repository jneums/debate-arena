/**
 * Prometheus Protocol Compliance Tests
 *
 * Validates the MCP server meets Prometheus Protocol requirements:
 * - HTTP endpoints serve content
 * - Auth is properly configured (401 without session)
 * - Beacon timer starts on install
 * - Owner system is functional
 */

import { describe, beforeAll, afterAll, it, expect, inject } from 'vitest';
import { PocketIc, createIdentity } from '@dfinity/pic';
import { AnonymousIdentity } from '@icp-sdk/core/agent';
import { idlFactory as mcpServerIdlFactory } from '../.dfx/local/canisters/debate_arena/service.did.js';
import type { _SERVICE as McpServerService } from '../.dfx/local/canisters/debate_arena/service.did.d.ts';
import type { Actor } from '@dfinity/pic';
import path from 'node:path';

const MCP_SERVER_WASM_PATH = path.resolve(
  __dirname,
  '../.dfx/local/canisters/debate_arena/debate_arena.wasm',
);

describe('MCP Server Requirements', () => {
  let pic: PocketIc;
  let serverActor: Actor<McpServerService>;
  let canisterId: any;
  let testOwner = createIdentity('test-owner');

  beforeAll(async () => {
    const picUrl = inject('PIC_URL');
    pic = await PocketIc.create(picUrl);
    canisterId = await pic.createCanister();

    await pic.installCode({
      canisterId,
      wasm: MCP_SERVER_WASM_PATH,
      caller: testOwner,
    });

    serverActor = pic.createActor<McpServerService>(
      mcpServerIdlFactory,
      canisterId,
    );
  });

  afterAll(async () => {
    await pic?.tearDown();
  });

  describe('HTTP Endpoints', () => {
    it('should serve a landing page at /', async () => {
      serverActor.setIdentity(new AnonymousIdentity());
      const httpResponse = await serverActor.http_request({
        method: 'GET',
        url: '/',
        headers: [],
        body: new Uint8Array(),
        certificate_version: [],
      });
      expect(httpResponse.status_code).toBe(200);
      const body = new TextDecoder().decode(httpResponse.body as Uint8Array);
      expect(body).toContain('Debate Arena');
      expect(body).toContain('/mcp');
    });
  });

  describe('Auth Configuration', () => {
    it('should enforce auth on MCP endpoint', async () => {
      serverActor.setIdentity(new AnonymousIdentity());
      const rpcPayload = {
        jsonrpc: '2.0',
        method: 'tools/list',
        params: {},
        id: 'test-auth',
      };
      const body = new TextEncoder().encode(JSON.stringify(rpcPayload));

      const httpResponse = await serverActor.http_request_update({
        method: 'POST',
        url: '/mcp',
        headers: [['Content-Type', 'application/json']],
        body,
        certificate_version: [],
      });

      expect(httpResponse.status_code).toBe(401);
    });
  });

  describe('Owner System', () => {
    it('should have a functional owner', async () => {
      serverActor.setIdentity(testOwner);
      const owner = await serverActor.get_owner();
      const ownerText = owner.toText();
      expect(typeof ownerText).toBe('string');
      expect(ownerText.length).toBeGreaterThan(0);
    });
  });

  describe('Upgrade Lifecycle', () => {
    it('should report upgrade finished successfully', async () => {
      serverActor.setIdentity(testOwner);
      const result = await serverActor.icrc120_upgrade_finished();
      expect(result).toHaveProperty('Success');
    });
  });
});
