import {onRequest} from "firebase-functions/v2/https";

// v210: Lazy imports to avoid deployment timeout
// All heavy modules are loaded on first request, not at initialization

// Type imports only (no runtime cost)
import type * as AdminType from "firebase-admin";
import type {ChatRequest, UserProfile} from "./types/chat";

// Cached lazy-loaded modules
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminModule: typeof AdminType | null = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let adminApp: AdminType.app.App | null = null;
// eslint-disable-next-line @typescript-eslint/no-explicit-any
let openaiClient: any = null;

function getAdmin(): typeof AdminType {
  if (!adminModule) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    adminModule = require("firebase-admin");
  }
  if (!adminApp) {
    adminApp = adminModule!.initializeApp();
  }
  return adminModule!;
}

function getOpenAI() {
  if (!openaiClient) {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const OpenAI = require("openai").default;
    openaiClient = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });
  }
  return openaiClient;
}

// Lazy-loaded helper modules
function getAuth() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  return require("./auth");
}

function getPrompts() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  return require("./prompts/systemPrompt");
}

function getTools() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  return require("./tools/definitions");
}

function getHandlers() {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  return require("./handlers");
}

/**
 * Load user profile from Firestore
 */
async function loadUserProfile(
  uid: string,
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  db: any
): Promise<UserProfile> {
  const userDoc = await db.collection("users").doc(uid).get();

  if (!userDoc.exists) {
    // Return minimal profile for new users
    return {uid};
  }

  const data = userDoc.data()!;
  return {
    uid,
    email: data.email,
    displayName: data.displayName,
    profile: data.profile,
    role: data.role,
    gymId: data.gymId,
    trainerId: data.trainerId,
  };
}

/**
 * Hello World - Test endpoint
 * GET /api/hello
 */
export const hello = onRequest({cors: true, invoker: "public"}, (req, res) => {
  res.json({
    message: "Hello from Medina!",
    timestamp: new Date().toISOString(),
  });
});

/**
 * Chat endpoint - OpenAI Responses API with streaming
 * POST /api/chat
 *
 * Request body:
 * {
 *   messages: [{ role: "user", content: "..." }],
 *   previousResponseId?: string
 * }
 *
 * Response: Server-Sent Events (SSE) stream
 */
export const chat = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 120},
  async (req, res) => {
    // Only allow POST
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // 1. Verify Firebase auth token
      const adminSdk = getAdmin();
      let uid: string;

      try {
        const {verifyAuth} = getAuth();
        const decoded = await verifyAuth(req, adminSdk);
        uid = decoded.uid;
      } catch (error: unknown) {
        const {AuthError} = getAuth();
        if (error instanceof AuthError) {
          const authErr = error as { statusCode: number; message: string };
          res.status(authErr.statusCode).json({error: authErr.message});
          return;
        }
        throw error;
      }

      // 2. Validate request body
      const body = req.body as ChatRequest;

      // Support two modes:
      // A) New message: messages array required
      // B) Tool continuation: toolOutputs + previousResponseId (no messages needed)
      const isToolContinuation = body.toolOutputs && body.toolOutputs.length > 0 && body.previousResponseId;
      const hasMessages = body.messages && Array.isArray(body.messages) && body.messages.length > 0;

      if (!hasMessages && !isToolContinuation) {
        res.status(400).json({error: "messages array is required (or toolOutputs + previousResponseId for continuation)"});
        return;
      }

      // 3. Load user profile from Firestore
      const db = adminSdk.firestore();
      const user = await loadUserProfile(uid, db);

      // 4. Build system prompt with user context
      const {buildSystemPrompt} = getPrompts();
      const systemPrompt = buildSystemPrompt(user);

      // v204: Debug logging for prompt verification
      console.log(`System prompt built for ${uid}, includes update_profile instructions: ${systemPrompt.includes("update_profile")}`);

      // 5. Get tool definitions
      const {getToolDefinitions} = getTools();
      const tools = getToolDefinitions();

      // 6. Call OpenAI Responses API with streaming
      const openai = getOpenAI();

      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      let requestOptions: any;

      if (isToolContinuation) {
        // Tool continuation mode: iOS executed tool, send outputs to OpenAI
        console.log(`Tool continuation from ${uid}: ${body.toolOutputs!.length} outputs, responseId=${body.previousResponseId}`);

        // Format tool outputs for OpenAI
        const formattedOutputs = body.toolOutputs!.map((output) => ({
          type: "function_call_output",
          call_id: output.call_id,
          output: output.output,
        }));

        requestOptions = {
          model: "gpt-4o-mini",
          previous_response_id: body.previousResponseId,
          input: formattedOutputs,
          stream: true,
        };
      } else {
        // Normal message mode: Convert messages to OpenAI format
        const input = body.messages!.map((msg) => ({
          role: msg.role as "user" | "assistant" | "system",
          content: msg.content,
        }));

        requestOptions = {
          model: "gpt-4o-mini",
          input,
          instructions: systemPrompt,
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          tools: tools.map((t: any) => ({
            type: t.type,
            name: t.name,
            description: t.description,
            parameters: t.parameters,
          })),
          stream: true,
        };

        // Add conversation continuity if provided
        if (body.previousResponseId) {
          requestOptions.previous_response_id = body.previousResponseId;
        }

        console.log(`Chat request from ${uid}: ${body.messages!.length} messages`);
      }

      // 7. Stream SSE to client
      res.setHeader("Content-Type", "text/event-stream");
      res.setHeader("Cache-Control", "no-cache");
      res.setHeader("Connection", "keep-alive");
      res.setHeader("X-Accel-Buffering", "no"); // Disable nginx buffering

      const stream = await openai.responses.create(requestOptions);

      // Track tool calls for server-side execution
      interface PendingToolCall {
        id: string;
        name: string;
        arguments: string;
      }
      const pendingToolCalls: PendingToolCall[] = [];
      let currentResponseId: string | null = null;

      // Track which tool calls are being handled server-side
      // Maps item_id -> { name, callId }
      const serverHandledItems = new Map<string, { name: string; callId: string }>();

      // v207: Track passthrough tool calls - if ANY passthrough exists, we MUST send completion
      // Bug fix: Previously completion was suppressed whenever serverHandledItems.size > 0,
      // but iOS needs completion to trigger tool execution for passthrough tools
      let passthroughToolCount = 0;

      // Stream events to client
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const asyncStream = stream as unknown as AsyncIterable<any>;
      for await (const event of asyncStream) {
        const eventType = event.type || "message";

        // Track response ID for continuation
        if (eventType === "response.created" && event.response?.id) {
          currentResponseId = event.response.id;
        }

        // Detect new tool call - check if we should handle it server-side
        if (eventType === "response.output_item.added") {
          const item = event.item;
          if (item?.type === "function_call" && item?.name) {
            // v204: Log ALL tool calls for debugging
            console.log(`Tool call detected: ${item.name} (call_id: ${item.call_id})`);

            const {hasHandler} = getHandlers();
            if (hasHandler(item.name)) {
              // Mark this item as server-handled so we suppress all its events
              // Store the item ID, tool name, and call_id for later use
              serverHandledItems.set(item.id, {
                name: item.name,
                callId: item.call_id,
              });
              console.log(`  → Server handling tool: ${item.name}`);
              continue; // Don't stream to iOS
            } else {
              // v207: Track passthrough tool calls
              passthroughToolCount++;
              console.log(`  → Passing to iOS: ${item.name} (passthrough #${passthroughToolCount})`);
            }
          }
        }

        // Suppress argument streaming for server-handled tools
        if (eventType === "response.function_call_arguments.delta") {
          const itemId = event.item_id;
          if (itemId && serverHandledItems.has(itemId)) {
            continue; // Don't stream to iOS
          }
        }

        // Collect completed tool calls for server execution
        if (eventType === "response.function_call_arguments.done") {
          const itemId = event.item_id;
          const toolInfo = serverHandledItems.get(itemId);
          if (itemId && toolInfo) {
            const args = event.arguments || "{}";

            pendingToolCalls.push({
              id: toolInfo.callId,
              name: toolInfo.name,
              arguments: args,
            });
            console.log(`Server handler queued: ${toolInfo.name} (call_id: ${toolInfo.callId})`);
            continue; // Don't stream to iOS
          }
        }

        // Suppress output_item.done for server-handled tool calls
        if (eventType === "response.output_item.done") {
          const itemId = event.item?.id;
          if (itemId && serverHandledItems.has(itemId)) {
            continue; // Don't stream to iOS
          }
        }

        // v207: Suppress completion events ONLY when ALL tools are server-handled
        // If there are ANY passthrough tools, iOS needs the completion to trigger tool execution
        // The continuation stream will send its own completion events for server-only cases
        if (serverHandledItems.size > 0 && passthroughToolCount === 0) {
          if (eventType === "response.completed" || eventType === "response.done") {
            console.log(`Suppressing ${eventType} - all tools server-handled`);
            continue; // Don't stream to iOS
          }
        }

        // Stream all other events to client
        res.write(`event: ${eventType}\n`);
        res.write(`data: ${JSON.stringify(event)}\n\n`);
      }

      // Execute server-side handlers if any
      if (pendingToolCalls.length > 0 && currentResponseId) {
        console.log(`Executing ${pendingToolCalls.length} server handler(s)`);

        // Execute all pending handlers
        const toolOutputs: Array<{type: string; call_id: string; output: string}> = [];
        const allChips: Array<{label: string; command: string}> = [];
        // v210: Collect workout cards for inline display
        const allWorkoutCards: Array<{workoutId: string; workoutName: string}> = [];
        // v210: Collect plan cards for inline display
        const allPlanCards: Array<{planId: string; planName: string; workoutCount: number; durationWeeks: number}> = [];

        for (const toolCall of pendingToolCalls) {
          let parsedArgs: Record<string, unknown> = {};
          try {
            parsedArgs = JSON.parse(toolCall.arguments);
          } catch {
            console.error(`Failed to parse args for ${toolCall.name}`);
          }

          const {executeHandler} = getHandlers();
          const result = await executeHandler(
            toolCall.name,
            parsedArgs,
            {uid, db}
          );

          if (result) {
            console.log(`[chat] Handler ${toolCall.name} returned:`, {
              hasOutput: !!result.output,
              hasChips: !!result.suggestionChips,
              hasWorkoutCard: !!result.workoutCard,
              hasPlanCard: !!result.planCard,
              workoutCard: result.workoutCard,
              planCard: result.planCard,
            });

            toolOutputs.push({
              type: "function_call_output",
              call_id: toolCall.id,
              output: result.output,
            });

            // Collect suggestion chips
            if (result.suggestionChips) {
              allChips.push(...result.suggestionChips);
            }

            // v210: Collect workout cards
            if (result.workoutCard) {
              allWorkoutCards.push(result.workoutCard);
            }

            // v210: Collect plan cards
            if (result.planCard) {
              allPlanCards.push(result.planCard);
            }
          }
        }

        // Continue conversation with tool outputs
        if (toolOutputs.length > 0) {
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const continueOptions: any = {
            model: "gpt-4o-mini",
            previous_response_id: currentResponseId,
            input: toolOutputs,
            stream: true,
          };

          const continueStream = await openai.responses.create(continueOptions);
          // eslint-disable-next-line @typescript-eslint/no-explicit-any
          const continueAsyncStream = continueStream as unknown as AsyncIterable<any>;

          for await (const event of continueAsyncStream) {
            const eventType = event.type || "message";
            res.write(`event: ${eventType}\n`);
            res.write(`data: ${JSON.stringify(event)}\n\n`);
          }

          // Send suggestion chips as custom event if any
          if (allChips.length > 0) {
            res.write(`event: suggestion_chips\n`);
            res.write(`data: ${JSON.stringify({chips: allChips})}\n\n`);
          }

          // v210: Send workout cards as custom event if any
          console.log(`[chat] Workout cards to send: ${allWorkoutCards.length}`);
          if (allWorkoutCards.length > 0) {
            console.log(`[chat] Sending workout_card event:`, JSON.stringify(allWorkoutCards));
            res.write(`event: workout_card\n`);
            res.write(`data: ${JSON.stringify({cards: allWorkoutCards})}\n\n`);
          }

          // v210: Send plan cards as custom event if any
          console.log(`[chat] Plan cards to send: ${allPlanCards.length}`);
          if (allPlanCards.length > 0) {
            console.log(`[chat] Sending plan_card event:`, JSON.stringify(allPlanCards));
            res.write(`event: plan_card\n`);
            res.write(`data: ${JSON.stringify({cards: allPlanCards})}\n\n`);
          }
        }
      }

      res.end();
    } catch (error) {
      console.error("Chat error:", error);

      // If headers already sent (streaming started), send error as SSE
      if (res.headersSent) {
        res.write(
          `data: ${JSON.stringify({
            type: "error",
            error: {message: "Stream error occurred"},
          })}\n\n`
        );
        res.end();
        return;
      }

      // Otherwise send JSON error
      const errorMessage =
        error instanceof Error ? error.message : "Internal server error";
      res.status(500).json({error: errorMessage});
    }
  }
);

/**
 * Seed exercises to Firestore
 * POST /seedExercises
 * Body: { exercises: { [id]: Exercise } }
 * Admin-only: Protected by simple secret (not for production)
 */
export const seedExercises = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 300},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    // Simple secret protection (NOT for production - use proper auth)
    const secret = req.headers["x-seed-secret"];
    if (secret !== "medina-seed-2024") {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    try {
      const {exercises} = req.body;
      if (!exercises || typeof exercises !== "object") {
        res.status(400).json({error: "exercises object is required"});
        return;
      }

      const adminSdk = getAdmin();
      const db = adminSdk.firestore();

      const exerciseIds = Object.keys(exercises);
      console.log(`Seeding ${exerciseIds.length} exercises`);

      // Firestore batch writes are limited to 500 operations
      const BATCH_SIZE = 500;
      let totalWritten = 0;

      for (let i = 0; i < exerciseIds.length; i += BATCH_SIZE) {
        const batch = db.batch();
        const chunk = exerciseIds.slice(i, i + BATCH_SIZE);

        for (const exerciseId of chunk) {
          const docRef = db.collection("exercises").doc(exerciseId);
          batch.set(docRef, exercises[exerciseId]);
        }

        await batch.commit();
        totalWritten += chunk.length;
        console.log(`Wrote ${totalWritten}/${exerciseIds.length} exercises`);
      }

      res.json({
        success: true,
        count: totalWritten,
        message: `Seeded ${totalWritten} exercises to Firestore`,
      });
    } catch (error) {
      console.error("Seed exercises error:", error);
      res.status(500).json({error: "Failed to seed exercises"});
    }
  }
);

/**
 * Seed protocols to Firestore
 * POST /seedProtocols
 * Body: { protocols: { [id]: ProtocolConfig } }
 * Admin-only: Protected by simple secret (not for production)
 */
export const seedProtocols = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 300},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    const secret = req.headers["x-seed-secret"];
    if (secret !== "medina-seed-2024") {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    try {
      const {protocols} = req.body;
      if (!protocols || typeof protocols !== "object") {
        res.status(400).json({error: "protocols object is required"});
        return;
      }

      const adminSdk = getAdmin();
      const db = adminSdk.firestore();

      const protocolIds = Object.keys(protocols);
      console.log(`Seeding ${protocolIds.length} protocols`);

      const batch = db.batch();
      for (const protocolId of protocolIds) {
        const docRef = db.collection("protocols").doc(protocolId);
        batch.set(docRef, {
          ...protocols[protocolId],
          createdAt: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      res.json({
        success: true,
        count: protocolIds.length,
        message: `Seeded ${protocolIds.length} protocols to Firestore`,
      });
    } catch (error) {
      console.error("Seed protocols error:", error);
      res.status(500).json({error: "Failed to seed protocols"});
    }
  }
);

/**
 * Seed gyms to Firestore
 * POST /seedGyms
 * Body: { gyms: { [id]: Gym } }
 * Admin-only: Protected by simple secret (not for production)
 */
export const seedGyms = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 300},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    const secret = req.headers["x-seed-secret"];
    if (secret !== "medina-seed-2024") {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    try {
      const {gyms} = req.body;
      if (!gyms || typeof gyms !== "object") {
        res.status(400).json({error: "gyms object is required"});
        return;
      }

      const adminSdk = getAdmin();
      const db = adminSdk.firestore();

      const gymIds = Object.keys(gyms);
      console.log(`Seeding ${gymIds.length} gyms`);

      const batch = db.batch();
      for (const gymId of gymIds) {
        const docRef = db.collection("gyms").doc(gymId);
        batch.set(docRef, {
          ...gyms[gymId],
          createdAt: getAdmin().firestore.FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      res.json({
        success: true,
        count: gymIds.length,
        message: `Seeded ${gymIds.length} gyms to Firestore`,
      });
    } catch (error) {
      console.error("Seed gyms error:", error);
      res.status(500).json({error: "Failed to seed gyms"});
    }
  }
);

/**
 * Get user profile
 * GET /api/user
 * Requires: Authorization header with Firebase ID token
 */
export const getUser = onRequest({cors: true, invoker: "public"}, async (req, res) => {
  try {
    // Verify auth token
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith("Bearer ")) {
      res.status(401).json({error: "Unauthorized"});
      return;
    }

    const idToken = authHeader.split("Bearer ")[1];
    const adminSdk = getAdmin();
    const decodedToken = await adminSdk.auth().verifyIdToken(idToken);
    const uid = decodedToken.uid;

    // Get user from Firestore
    const db = adminSdk.firestore();
    const userDoc = await db.collection("users").doc(uid).get();

    const now = new Date().toISOString();

    if (!userDoc.exists) {
      // Create new user document
      const newUser = {
        uid,
        email: decodedToken.email || "",
        displayName: decodedToken.name || "",
        profile: {},
        createdAt: now,
        updatedAt: now,
      };
      await db.collection("users").doc(uid).set(newUser);
      res.json(newUser);
      return;
    }

    // Convert Firestore timestamps to ISO strings for iOS compatibility
    const userData = userDoc.data()!;
    const response = {
      ...userData,
      createdAt: userData.createdAt?.toDate?.()?.toISOString() || userData.createdAt || now,
      updatedAt: userData.updatedAt?.toDate?.()?.toISOString() || userData.updatedAt || now,
    };
    res.json(response);
  } catch (error) {
    console.error("Get user error:", error);
    res.status(500).json({error: "Internal server error"});
  }
});

/**
 * Text-to-Speech endpoint - Proxies OpenAI TTS API
 * POST /api/tts
 * Body: { text: string, voice?: string, speed?: number }
 * Returns: audio/mpeg binary data
 *
 * Requires: Authorization header with Firebase ID token
 */
export const tts = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 60},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // Verify Firebase auth token
      const authHeader = req.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const idToken = authHeader.split("Bearer ")[1];
      const adminSdk = getAdmin();
      const decodedToken = await adminSdk.auth().verifyIdToken(idToken);
      const uid = decodedToken.uid;

      // Validate request body
      const {text, voice = "nova", speed = 1.0} = req.body;

      if (!text || typeof text !== "string") {
        res.status(400).json({error: "text is required"});
        return;
      }

      console.log(`TTS request from ${uid}: ${text.substring(0, 50)}... (voice: ${voice})`);

      // Call OpenAI TTS API
      const openai = getOpenAI();
      const response = await openai.audio.speech.create({
        model: "tts-1",
        voice: voice,
        input: text,
        response_format: "mp3",
        speed: speed,
      });

      // Get audio data as buffer
      const audioBuffer = Buffer.from(await response.arrayBuffer());

      // Return audio data
      res.setHeader("Content-Type", "audio/mpeg");
      res.setHeader("Content-Length", audioBuffer.length.toString());
      res.send(audioBuffer);
    } catch (error) {
      console.error("TTS error:", error);
      const errorMessage = error instanceof Error ? error.message : "TTS failed";
      res.status(500).json({error: errorMessage});
    }
  }
);

/**
 * Vision endpoint - Proxies OpenAI Vision API for image analysis
 * POST /api/vision
 * Body: { imageBase64: string, prompt: string, model?: string, jsonMode?: boolean }
 * Returns: { content: string }
 *
 * Requires: Authorization header with Firebase ID token
 */
export const vision = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 120},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // Verify Firebase auth token
      const authHeader = req.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const idToken = authHeader.split("Bearer ")[1];
      const adminSdk = getAdmin();
      const decodedToken = await adminSdk.auth().verifyIdToken(idToken);
      const uid = decodedToken.uid;

      // Validate request body
      const {imageBase64, prompt, model = "gpt-4o", jsonMode = false} = req.body;

      if (!imageBase64 || typeof imageBase64 !== "string") {
        res.status(400).json({error: "imageBase64 is required"});
        return;
      }

      if (!prompt || typeof prompt !== "string") {
        res.status(400).json({error: "prompt is required"});
        return;
      }

      console.log(`Vision request from ${uid}: prompt length ${prompt.length}, image size ${imageBase64.length}, jsonMode: ${jsonMode}`);

      // Call OpenAI Vision API
      const openai = getOpenAI();
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const requestOptions: any = {
        model: model,
        messages: [
          {
            role: "user",
            content: [
              {type: "text", text: prompt},
              {
                type: "image_url",
                image_url: {
                  url: `data:image/jpeg;base64,${imageBase64}`,
                },
              },
            ],
          },
        ],
        max_tokens: 4096,
      };

      // Add JSON mode if requested
      if (jsonMode) {
        requestOptions.response_format = {type: "json_object"};
      }

      const response = await openai.chat.completions.create(requestOptions);

      const content = response.choices[0]?.message?.content || "";
      console.log(`Vision response for ${uid}: ${content.substring(0, 100)}...`);

      res.json({content});
    } catch (error) {
      console.error("Vision error:", error);
      const errorMessage = error instanceof Error ? error.message : "Vision failed";
      res.status(500).json({error: errorMessage});
    }
  }
);

/**
 * Simple chat completion endpoint - Proxies OpenAI Chat API (non-streaming)
 * POST /api/chatSimple
 * Body: { messages: array, model?: string, temperature?: number }
 * Returns: { content: string }
 *
 * Use this for simple one-shot completions (announcements, extraction, etc.)
 * For conversation with tools, use /api/chat instead.
 *
 * Requires: Authorization header with Firebase ID token
 */
export const chatSimple = onRequest(
  {cors: true, invoker: "public", timeoutSeconds: 60},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({error: "Method not allowed"});
      return;
    }

    try {
      // Verify Firebase auth token
      const authHeader = req.headers.authorization;
      if (!authHeader?.startsWith("Bearer ")) {
        res.status(401).json({error: "Unauthorized"});
        return;
      }

      const idToken = authHeader.split("Bearer ")[1];
      const adminSdk = getAdmin();
      const decodedToken = await adminSdk.auth().verifyIdToken(idToken);
      const uid = decodedToken.uid;

      // Validate request body
      const {messages, model = "gpt-4o-mini", temperature = 0.7} = req.body;

      if (!messages || !Array.isArray(messages) || messages.length === 0) {
        res.status(400).json({error: "messages array is required"});
        return;
      }

      console.log(`ChatSimple request from ${uid}: ${messages.length} messages, model: ${model}`);

      // Call OpenAI Chat API
      const openai = getOpenAI();
      const response = await openai.chat.completions.create({
        model: model,
        messages: messages,
        temperature: temperature,
      });

      const content = response.choices[0]?.message?.content || "";
      console.log(`ChatSimple response for ${uid}: ${content.substring(0, 100)}...`);

      res.json({content});
    } catch (error) {
      console.error("ChatSimple error:", error);
      const errorMessage = error instanceof Error ? error.message : "Chat failed";
      res.status(500).json({error: errorMessage});
    }
  }
);

// Calculation endpoint - centralized formulas for iOS and web
export {calculate} from "./api/calculate";

// Import endpoint - CSV parsing, exercise matching, intelligence analysis
export {importCSV} from "./api/import";

// Exercise selection endpoint - library-first selection with experience fallback
export {selectExercises} from "./api/selectExercises";
