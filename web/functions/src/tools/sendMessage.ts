/**
 * Send Message Handler
 *
 * Creates a message from user to trainer (or vice versa).
 * Port of iOS SendMessageHandler.swift
 *
 * Parameters:
 *   recipientId: ID of the message recipient
 *   content: Message content
 *   messageType: (optional) Type of message (general, workout, plan, etc.)
 *   threadId: (optional) Existing thread ID for replies
 *   subject: (optional) Subject for new threads
 *
 * Firestore structure:
 *   messages/{messageId} → TrainerMessage
 *   threads/{threadId} → MessageThread
 */

import type {HandlerContext, HandlerResult} from "./index";
import {FieldValue} from "firebase-admin/firestore";

interface TrainerMessage {
  id: string;
  senderId: string;
  recipientId: string;
  content: string;
  messageType: string;
  threadId: string;
  subject?: string;
  replyToId?: string;
  createdAt: FirebaseFirestore.Timestamp;
  readAt?: FirebaseFirestore.Timestamp;
}

interface MessageThread {
  id: string;
  participantIds: string[];
  subject?: string;
  lastMessageId?: string;
  lastMessageContent?: string;
  lastMessageAt: FirebaseFirestore.Timestamp;
  createdAt: FirebaseFirestore.Timestamp;
}

/**
 * Generate a subject from message content
 */
function generateSubject(content: string): string {
  const firstSentence = content.split(/[.!?]/)[0] || content;
  const trimmed = firstSentence.trim();

  if (trimmed.length <= 50) {
    return trimmed;
  }
  return trimmed.substring(0, 47) + "...";
}

/**
 * Send a message to another user
 */
export async function sendMessageHandler(
  args: Record<string, unknown>,
  context: HandlerContext
): Promise<HandlerResult> {
  const {uid, db} = context;

  // Parse required parameters
  const recipientId = args.recipientId as string | undefined;
  if (!recipientId) {
    return {
      output: "ERROR: Missing required parameter 'recipientId'",
    };
  }

  const content = args.content as string | undefined;
  if (!content) {
    return {
      output: "ERROR: Missing required parameter 'content'",
    };
  }

  // Parse optional parameters
  const messageType = (args.messageType as string) || "general";
  const existingThreadId = args.threadId as string | undefined;
  const subject = args.subject as string | undefined;

  try {
    // Validate recipient exists
    const recipientRef = db.collection("users").doc(recipientId);
    const recipientDoc = await recipientRef.get();

    if (!recipientDoc.exists) {
      return {
        output: `ERROR: Recipient '${recipientId}' not found.`,
      };
    }

    const recipientData = recipientDoc.data();
    const recipientName = recipientData?.displayName ||
      recipientData?.email?.split("@")[0] ||
      recipientId;

    // Determine thread ID
    let threadId: string;
    let isNewThread: boolean;

    if (existingThreadId && existingThreadId.length > 0) {
      // Check if thread exists
      const threadRef = db.collection("threads").doc(existingThreadId);
      const threadDoc = await threadRef.get();

      if (!threadDoc.exists) {
        return {
          output: "ERROR: Thread not found",
        };
      }

      const threadData = threadDoc.data() as MessageThread;
      if (!threadData.participantIds.includes(uid)) {
        return {
          output: "ERROR: You are not a participant in this thread",
        };
      }

      threadId = existingThreadId;
      isNewThread = false;
    } else {
      // Create new thread
      threadId = db.collection("threads").doc().id;
      isNewThread = true;
    }

    // Create message
    const messageId = db.collection("messages").doc().id;
    const now = FieldValue.serverTimestamp();

    const message: Omit<TrainerMessage, "createdAt"> & {createdAt: FirebaseFirestore.FieldValue} = {
      id: messageId,
      senderId: uid,
      recipientId,
      content,
      messageType,
      threadId,
      subject: isNewThread ? (subject || generateSubject(content)) : undefined,
      createdAt: now,
    };

    // Create or update thread
    if (isNewThread) {
      const thread: Omit<MessageThread, "createdAt" | "lastMessageAt"> & {
        createdAt: FirebaseFirestore.FieldValue;
        lastMessageAt: FirebaseFirestore.FieldValue;
      } = {
        id: threadId,
        participantIds: [uid, recipientId],
        subject: subject || generateSubject(content),
        lastMessageId: messageId,
        lastMessageContent: content.substring(0, 100),
        lastMessageAt: now,
        createdAt: now,
      };

      await db.collection("threads").doc(threadId).set(thread);
    } else {
      await db.collection("threads").doc(threadId).update({
        lastMessageId: messageId,
        lastMessageContent: content.substring(0, 100),
        lastMessageAt: now,
      });
    }

    // Save message
    await db.collection("messages").doc(messageId).set(message);

    return {
      output: `SUCCESS: Message sent to ${recipientName}.`,
      suggestionChips: [
        {label: "View messages", command: "show my messages"},
        {label: "Send another", command: "send a message"},
      ],
    };
  } catch (error) {
    console.error("[sendMessage] Error:", error);
    return {
      output: `ERROR: Failed to send message. ${
        error instanceof Error ? error.message : "Unknown error"
      }`,
    };
  }
}
