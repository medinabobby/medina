/**
 * Plan API endpoints - REST wrappers for plan tools
 *
 * Enables iOS UI to call plan operations directly without going through chat.
 * All tools already exist - this just exposes them as REST endpoints.
 *
 * POST /api/plan/activate
 * POST /api/plan/abandon
 * POST /api/plan/delete
 * POST /api/plan/reschedule
 */

import {onRequest} from "firebase-functions/v2/https";
import {activatePlanHandler} from "../tools/activatePlan";
import {abandonPlanHandler} from "../tools/abandonPlan";
import {deletePlanHandler} from "../tools/deletePlan";
import {reschedulePlanHandler} from "../tools/reschedulePlan";
import {HandlerContext} from "../tools/index";

// Lazy-loaded admin module
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminModule: any = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminApp: any = null;

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function getAdmin(): any {
  if (!adminModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    adminModule = require("firebase-admin");
  }
  if (!adminApp) {
    if (adminModule.apps.length === 0) {
      adminApp = adminModule.initializeApp();
    } else {
      adminApp = adminModule.apps[0];
    }
  }
  return adminModule;
}

/**
 * Verify Firebase ID token and return uid
 */
async function verifyAuth(authHeader: string | undefined): Promise<string | null> {
  if (!authHeader?.startsWith("Bearer ")) {
    return null;
  }
  const token = authHeader.substring(7);
  try {
    const admin = getAdmin();
    const decoded = await admin.auth().verifyIdToken(token);
    return decoded.uid;
  } catch {
    return null;
  }
}

/**
 * Create handler context for calling tool handlers
 */
function createContext(uid: string): HandlerContext {
  const admin = getAdmin();
  return {
    uid,
    db: admin.firestore(),
  };
}

// MARK: - Activate Plan

export const activatePlan = onRequest(
  {cors: true, invoker: "public"},
  async (req, res) => {
    // Auth check
    const uid = await verifyAuth(req.headers.authorization);
    if (!uid) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      const context = createContext(uid);
      const result = await activatePlanHandler(req.body, context);

      res.json({
        success: !result.output?.startsWith("ERROR"),
        message: result.output,
        suggestionChips: result.suggestionChips,
      });
    } catch (error) {
      console.error("[activatePlan] Error:", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);

// MARK: - Abandon Plan

export const abandonPlan = onRequest(
  {cors: true, invoker: "public"},
  async (req, res) => {
    const uid = await verifyAuth(req.headers.authorization);
    if (!uid) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      const context = createContext(uid);
      const result = await abandonPlanHandler(req.body, context);

      res.json({
        success: !result.output?.startsWith("ERROR"),
        message: result.output,
        suggestionChips: result.suggestionChips,
      });
    } catch (error) {
      console.error("[abandonPlan] Error:", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);

// MARK: - Delete Plan

export const deletePlan = onRequest(
  {cors: true, invoker: "public"},
  async (req, res) => {
    const uid = await verifyAuth(req.headers.authorization);
    if (!uid) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      const context = createContext(uid);
      const result = await deletePlanHandler(req.body, context);

      res.json({
        success: !result.output?.startsWith("ERROR"),
        message: result.output,
        suggestionChips: result.suggestionChips,
      });
    } catch (error) {
      console.error("[deletePlan] Error:", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);

// MARK: - Reschedule Plan

export const reschedulePlan = onRequest(
  {cors: true, invoker: "public"},
  async (req, res) => {
    const uid = await verifyAuth(req.headers.authorization);
    if (!uid) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      const context = createContext(uid);
      const result = await reschedulePlanHandler(req.body, context);

      res.json({
        success: !result.output?.startsWith("ERROR"),
        message: result.output,
        suggestionChips: result.suggestionChips,
      });
    } catch (error) {
      console.error("[reschedulePlan] Error:", error);
      res.status(500).json({error: "Internal server error"});
    }
  }
);
