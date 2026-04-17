/**
 * Debate Arena Tool-Specific Tests
 *
 * Tests canister health, auth enforcement, and owner management.
 * Note: In PocketIC, the deployer principal from `shared ({caller = deployer})`
 * resolves to the management canister, not our test identity. We use set_owner
 * to take ownership after install.
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

describe('Debate Arena Tools', () => {
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

  describe('Canister health', () => {
    it('should have a valid owner principal', async () => {
      serverActor.setIdentity(testOwner);
      const owner = await serverActor.get_owner();
      const ownerText = owner.toText();
      expect(typeof ownerText).toBe('string');
      expect(ownerText.length).toBeGreaterThan(0);
    });

    it('should serve the landing page at /', async () => {
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
    });

    it('should return 404 for unknown paths', async () => {
      serverActor.setIdentity(new AnonymousIdentity());
      const httpResponse = await serverActor.http_request({
        method: 'GET',
        url: '/nonexistent',
        headers: [],
        body: new Uint8Array(),
        certificate_version: [],
      });
      expect(httpResponse.status_code).toBe(404);
    });
  });

  describe('Auth enforcement', () => {
    it('should return 401 for unauthenticated MCP calls', async () => {
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

  describe('Upgrade lifecycle', () => {
    it('should report upgrade finished successfully', async () => {
      serverActor.setIdentity(testOwner);
      const result = await serverActor.icrc120_upgrade_finished();
      expect(result).toHaveProperty('Success');
    });
  });
});
