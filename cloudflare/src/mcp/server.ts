import { McpServer } from '@modelcontextprotocol/server'
import { APP_VERSION } from '../version'
import { SERVER_INSTRUCTIONS } from './instructions'
import { registerPrompts } from './prompts'
import { registerAthleteTools } from './tools/athlete'
import { registerCatalogTools } from './tools/catalog'
import { registerProposalReadTools } from './tools/proposals'
import { registerProposeTools } from './tools/propose'
import { registerRecoveryTools } from './tools/recovery'
import { registerTrainingTools } from './tools/training'

/**
 * The openGym MCP server (contract §5): read tools over the owner's data, proposal tools, the
 * athlete-profile writer and the Coach prompts. `createMcpHandler` builds one per request
 * (stateless); tools never read auth context, since the OAuth provider only routes the owner here.
 */
export function createServer(env: Env): McpServer {
  const server = new McpServer({ name: 'opengym', title: 'openGym', version: APP_VERSION }, { instructions: SERVER_INSTRUCTIONS })
  registerTrainingTools(server, env.DB)
  registerRecoveryTools(server, env.DB)
  registerCatalogTools(server, env.DB)
  registerProposalReadTools(server, env.DB)
  registerProposeTools(server, env.DB)
  registerAthleteTools(server, env.DB)
  registerPrompts(server)
  return server
}
