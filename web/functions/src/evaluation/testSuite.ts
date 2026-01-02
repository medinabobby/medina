/**
 * AI Model Evaluation Test Suite
 *
 * v252: Test cases for comparing AI models on fitness coaching tasks.
 *
 * Categories:
 * - tool_calling: Verify correct tool invocations
 * - fitness_accuracy: Verify fitness knowledge
 * - tone: Verify coaching style and off-topic handling
 * - speed: Verify response time for simple queries
 *
 * Intent Classification (v247):
 * - Explicit commands → immediate tool execution
 * - Preference statements → confirmation first (expectedTool: null)
 * - Multi-param requests → clarifying questions (expectedTool: null)
 * - Data provision → immediate tool execution
 * - Destructive actions → confirmation first (expectedTool: null)
 */

export interface TestCase {
  id: string;
  category: 'tool_calling' | 'fitness_accuracy' | 'tone' | 'speed' | 'onboarding' | 'import' | 'tier';
  prompt: string;
  expectedTool?: string | null;  // Which tool should be called (null = no tool)
  expectedTopics?: string[];     // Keywords that should appear in response
  maxResponseTime?: number;      // ms - for speed tests
  description?: string;          // Human-readable description
  latencyCategory: 'basic' | 'tool_call' | 'vision';  // v251: For separate latency metrics

  // v252: Intent detection grading
  intentClarity: 'high' | 'medium' | 'low' | 'n/a';  // How obvious is user's intent? (n/a for knowledge questions)
  // HIGH: "Update my profile to 4 days" → execute immediately
  // MEDIUM: "My bench 1RM is 225" → ask or execute both OK
  // LOW: "I want to train 4 days" → should ask first
  isRiskyAction?: boolean;                 // Destructive actions (delete, etc.) - MUST ask confirmation
  followUpPrompt?: string;                 // What to send if AI asks for confirmation
  acceptableTools?: string[];              // Alternative correct tools (partial credit)

  // v253: Multimodal support
  testType?: 'text' | 'vision' | 'url_import';  // Default: 'text'
  imageFixture?: string;                   // Filename in fixtures/ directory (for vision tests)
  importUrl?: string;                      // URL to fetch and import (for url_import tests)
  expectedExtractions?: string[];          // Expected exercise names from vision/url extraction
  tierRecommendation?: 'fast' | 'standard' | 'smart' | 'vision';  // For tier tests
}

export const TEST_CASES: TestCase[] = [
  // =========================================================================
  // TOOL CALLING TESTS (10)
  // Verify AI correctly invokes the right tools
  // =========================================================================
  {
    id: 'TC01',
    category: 'tool_calling',
    prompt: 'Create a 45-minute push workout for tomorrow',
    expectedTool: 'create_workout',
    description: 'Should call create_workout with duration and splitDay',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'TC02',
    category: 'tool_calling',
    prompt: 'Show my schedule for this week',
    expectedTool: 'show_schedule',
    description: 'Should call show_schedule with week period',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, show it',
  },
  {
    id: 'TC03',
    category: 'tool_calling',
    prompt: 'My bench press 1RM is 225 lbs',
    expectedTool: 'update_exercise_target',
    description: 'Should call update_exercise_target, NOT update_profile',
    latencyCategory: 'tool_call',
    intentClarity: 'medium',  // User providing data - ask or execute both OK
    followUpPrompt: 'Yes, save that',
  },
  {
    id: 'TC04',
    category: 'tool_calling',
    prompt: "Skip today's workout",
    expectedTool: 'skip_workout',
    description: 'Should call skip_workout for the current day',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, skip it',
  },
  {
    id: 'TC05',
    category: 'tool_calling',
    prompt: 'Create a 12-week strength program',
    expectedTool: null,
    description: 'Multi-param request - AI should ask clarifying questions (goal, days/week) before creating plan',
    latencyCategory: 'basic',
    intentClarity: 'low',  // Missing required params, asking is correct
  },
  {
    id: 'TC06',
    category: 'tool_calling',
    prompt: 'Add bench press to my library',
    expectedTool: 'add_to_library',
    description: 'Should call add_to_library with exercise ID',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, add it',
  },
  {
    id: 'TC07',
    category: 'tool_calling',
    prompt: "I'm 30 years old and weigh 180 lbs",
    expectedTool: null,
    description: 'Should NOT auto-update - user stating info is not requesting update. AI should confirm first.',
    latencyCategory: 'basic',
    intentClarity: 'low',  // User stating info, not explicit command
    followUpPrompt: 'Yes, update my profile',
    acceptableTools: ['update_profile'],  // Acceptable if user confirms
  },
  {
    id: 'TC08',
    category: 'tool_calling',
    prompt: 'Swap the barbell row for something else',
    expectedTool: 'get_substitution_options',
    description: 'Should call get_substitution_options for alternatives',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, show me options',
  },
  {
    id: 'TC09',
    category: 'tool_calling',
    prompt: "What's the difference between strength and hypertrophy training?",
    expectedTool: null,
    description: 'Should NOT call any tool - just answer the question',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question, no tool expected
  },
  {
    id: 'TC10',
    category: 'tool_calling',
    prompt: 'I want to train 4 days per week',
    expectedTool: null,
    description: 'Preference statement - AI should ask confirmation before updating profile ("Want me to save this?")',
    latencyCategory: 'basic',
    intentClarity: 'low',  // Preference statement, not command
    followUpPrompt: 'Yes, save that preference',
    acceptableTools: ['update_profile'],  // Acceptable if user confirms
  },

  // =========================================================================
  // FITNESS ACCURACY TESTS (10)
  // Verify AI has correct fitness knowledge - NO TOOLS expected
  // =========================================================================
  {
    id: 'FA01',
    category: 'fitness_accuracy',
    prompt: 'What muscles does the Romanian deadlift target?',
    expectedTool: null,  // Knowledge question, no tool
    expectedTopics: ['hamstrings', 'glutes', 'lower back', 'posterior'],
    description: 'Should mention key posterior chain muscles',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA02',
    category: 'fitness_accuracy',
    prompt: 'How should I breathe during a bench press?',
    expectedTool: null,
    expectedTopics: ['inhale', 'exhale', 'brace', 'lower', 'press'],
    description: 'Should explain breathing pattern for bench press',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA03',
    category: 'fitness_accuracy',
    prompt: 'What rep range builds the most muscle?',
    expectedTool: null,
    expectedTopics: ['8', '12', 'hypertrophy', 'volume'],
    description: 'Should mention 8-12 rep range for hypertrophy',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA04',
    category: 'fitness_accuracy',
    prompt: 'How long should I rest between heavy compound sets?',
    expectedTool: null,
    expectedTopics: ['2', '3', '5', 'minute', 'recovery', 'strength'],
    description: 'Should recommend 2-5 minutes for heavy compounds',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA05',
    category: 'fitness_accuracy',
    prompt: 'Should I lift through lower back pain?',
    expectedTool: null,
    expectedTopics: ['stop', 'doctor', 'pain', 'injury', 'rest'],
    description: 'Should advise stopping and seeing a doctor',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA06',
    category: 'fitness_accuracy',
    prompt: "What's progressive overload?",
    expectedTool: null,
    expectedTopics: ['increase', 'weight', 'reps', 'volume', 'progress'],
    description: 'Should explain progressive overload principle',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA07',
    category: 'fitness_accuracy',
    prompt: 'Push pull legs vs upper lower split - which is better?',
    expectedTool: null,
    expectedTopics: ['frequency', 'recovery', 'depends', 'goals', 'schedule'],
    description: 'Should explain both have trade-offs, depends on goals',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA08',
    category: 'fitness_accuracy',
    prompt: 'How much protein do I need per day?',
    expectedTool: null,
    expectedTopics: ['0.7', '0.8', '1', 'gram', 'pound', 'bodyweight', 'protein'],
    description: 'Should mention 0.7-1g per pound of bodyweight',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA09',
    category: 'fitness_accuracy',
    prompt: 'Is it bad to train the same muscle two days in a row?',
    expectedTool: null,
    expectedTopics: ['recovery', '48', 'hours', 'rest', 'repair'],
    description: 'Should explain muscles need 48-72 hours to recover',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'FA10',
    category: 'fitness_accuracy',
    prompt: 'Can I build muscle in a calorie deficit?',
    expectedTool: null,
    expectedTopics: ['beginner', 'recomp', 'harder', 'protein', 'deficit'],
    description: 'Should explain it is possible but harder, easier for beginners',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },

  // =========================================================================
  // TONE/STYLE TESTS (5)
  // Verify coaching style and off-topic handling - NO TOOLS expected
  // =========================================================================
  {
    id: 'TN01',
    category: 'tone',
    prompt: "I'm struggling to stay motivated",
    expectedTool: null,  // Motivational response, no tool
    expectedTopics: ['normal', 'goals', 'small', 'habit', 'consistency'],
    description: 'Should be encouraging and offer practical advice',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Conversational, no tool expected
  },
  {
    id: 'TN02',
    category: 'tone',
    prompt: 'I missed 3 workouts this week',
    expectedTool: null,
    expectedTopics: ['okay', 'back', 'track', 'happens', 'start'],
    description: 'Should be supportive, not judgmental',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Conversational, no tool expected
  },
  {
    id: 'TN03',
    category: 'tone',
    prompt: 'What stocks should I buy?',
    expectedTool: null,  // Should politely decline
    expectedTopics: ['fitness', 'coach', 'expertise', 'workout', 'help'],
    description: 'Should politely decline and redirect to fitness',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Off-topic, no tool expected
  },
  {
    id: 'TN04',
    category: 'tone',
    prompt: 'Explain deload weeks',
    expectedTool: null,
    expectedTopics: ['recovery', 'reduce', 'intensity', 'fatigue', 'week'],
    description: 'Should explain deload concept clearly',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Knowledge question
  },
  {
    id: 'TN05',
    category: 'tone',
    prompt: 'I want to gain 50 lbs of muscle in 3 months',
    expectedTool: null,  // Should correct expectations, not create a plan
    expectedTopics: ['unrealistic', 'natural', 'rate', 'month', 'realistic'],
    description: 'Should gently correct unrealistic expectations',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Needs coaching, not tool execution
  },

  // =========================================================================
  // SPEED TESTS (5)
  // Verify response time for simple queries
  // =========================================================================
  {
    id: 'SP01',
    category: 'speed',
    prompt: 'Hi',
    expectedTool: null,  // Should NOT call any tool
    maxResponseTime: 2000,
    description: 'Simple greeting should be fast',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Greeting, no tool expected
  },
  {
    id: 'SP02',
    category: 'speed',
    prompt: 'Show my schedule',
    expectedTool: 'show_schedule',
    maxResponseTime: 5000,  // v251: Raised from 3000 - tool calls include Firestore ops
    description: 'Schedule query with tool call',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, show it',
  },
  {
    id: 'SP03',
    category: 'speed',
    prompt: 'What day is leg day?',
    expectedTool: null,  // General question, no tool needed
    maxResponseTime: 2500,
    description: 'Simple question about schedule',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Question, not command
  },
  {
    id: 'SP04',
    category: 'speed',
    prompt: 'Create a quick 30 min workout',
    expectedTool: 'create_workout',
    maxResponseTime: 8000,  // v251: Raised from 5000 - create_workout is slowest tool
    description: 'Workout creation with tool call',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'SP05',
    category: 'speed',
    prompt: 'Thanks!',
    expectedTool: null,  // Should NOT call any tool
    maxResponseTime: 2000,
    description: 'Simple acknowledgment should be fast',
    latencyCategory: 'basic',
    intentClarity: 'n/a',  // Acknowledgment, no tool expected
  },

  // =========================================================================
  // EXPLICIT COMMAND TESTS (v247)
  // Verify explicit commands trigger immediate tool execution
  // =========================================================================
  {
    id: 'TC11',
    category: 'tool_calling',
    prompt: 'Update my profile to train 4 days per week',
    expectedTool: 'update_profile',
    description: 'Explicit command - should update immediately (compare to TC10 preference statement)',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, update it',
  },
  {
    id: 'TC12',
    category: 'tool_calling',
    prompt: 'Save my schedule preference as Monday, Wednesday, Friday',
    expectedTool: 'update_profile',
    description: 'Explicit save command - should update profile immediately',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, save it',
  },

  // =========================================================================
  // PLAN MANAGEMENT TESTS (v247)
  // Verify destructive/commitment actions require confirmation
  // =========================================================================
  {
    id: 'PL01',
    category: 'tool_calling',
    prompt: 'Delete my current plan',
    expectedTool: null,
    description: 'Destructive action - AI should ask confirmation before deleting',
    latencyCategory: 'basic',
    intentClarity: 'high',
    isRiskyAction: true,  // Destructive - MUST ask confirmation
    followUpPrompt: 'Yes, delete it',
    acceptableTools: ['delete_plan'],  // Acceptable after confirmation
  },
  {
    id: 'PL02',
    category: 'tool_calling',
    prompt: 'Activate the strength plan',
    expectedTool: null,
    description: 'Multi-week commitment - AI should confirm before activating',
    latencyCategory: 'basic',
    intentClarity: 'low',  // Needs clarification (which plan?)
    followUpPrompt: 'Yes, activate it',
    acceptableTools: ['activate_plan'],  // Acceptable after confirmation
  },

  // =========================================================================
  // SYNONYM TESTS (v247)
  // Verify user terms are silently mapped to Medina concepts
  // =========================================================================
  {
    id: 'SY01',
    category: 'tool_calling',
    prompt: 'Create a 12-week program for muscle gain',
    expectedTool: null,
    description: 'Synonym "program" → plan; multi-param request should ask questions first',
    latencyCategory: 'basic',
    intentClarity: 'low',  // Missing required params (days/week, etc.)
  },
  {
    id: 'SY02',
    category: 'tool_calling',
    prompt: 'Show my routine for this week',
    expectedTool: 'show_schedule',
    description: 'Synonym "routine" → schedule; should show schedule immediately',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, show it',
  },

  // =========================================================================
  // EDGE CASE TESTS (v247)
  // Verify handling of ambiguous or extreme requests
  // =========================================================================
  {
    id: 'ED01',
    category: 'tool_calling',
    prompt: 'Update my profile',
    expectedTool: null,
    description: 'Incomplete command - AI should ask what to update',
    latencyCategory: 'basic',
    intentClarity: 'low',  // Missing what to update
  },
  {
    id: 'ED02',
    category: 'tool_calling',
    prompt: 'Create a workout',
    expectedTool: 'create_workout',
    description: 'Minimal command - should create workout using profile defaults',
    latencyCategory: 'tool_call',
    intentClarity: 'high',  // Clear command, can use defaults
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'ED03',
    category: 'tool_calling',
    prompt: 'I want to go from 2 to 7 days per week',
    expectedTool: null,
    description: 'Major change - AI should advise about overtraining risks before updating',
    latencyCategory: 'basic',
    intentClarity: 'low',  // Risky change, should discuss first
    isRiskyAction: true,  // Major lifestyle change
    followUpPrompt: 'Yes, update it anyway',
    acceptableTools: ['update_profile'],  // Acceptable after confirmation
  },
  {
    id: 'ED04',
    category: 'tool_calling',
    prompt: 'Remove bench press from my library',
    expectedTool: 'remove_from_library',
    description: 'Explicit removal command - reversible, should execute immediately',
    latencyCategory: 'tool_call',
    intentClarity: 'high',  // Clear command, reversible action
    followUpPrompt: 'Yes, remove it',
  },

  // =========================================================================
  // ONBOARDING FRICTION TESTS (v253)
  // Test zero-friction first value - how quickly can new users get started?
  // =========================================================================
  {
    id: 'OB01',
    category: 'onboarding',
    prompt: 'Give me a workout',
    expectedTool: 'create_workout',
    description: 'Minimum friction request - should create workout with defaults immediately',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'OB02',
    category: 'onboarding',
    prompt: 'I want to start lifting',
    expectedTool: null,
    description: 'Exploration - should suggest options or ask about goals',
    latencyCategory: 'basic',
    intentClarity: 'low',
    acceptableTools: ['suggest_options', 'create_workout'],
    followUpPrompt: 'Just give me a beginner workout',
  },
  {
    id: 'OB03',
    category: 'onboarding',
    prompt: 'Quick chest workout',
    expectedTool: 'create_workout',
    description: 'Specific body part request - should create chest-focused workout',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'OB04',
    category: 'onboarding',
    prompt: '30 minutes, I have dumbbells only',
    expectedTool: 'create_workout',
    description: 'Constraints given - should create dumbbell-only workout',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'OB05',
    category: 'onboarding',
    prompt: "I'm a beginner, help me start",
    expectedTool: null,
    description: 'Exploration - should offer guidance or suggestions',
    latencyCategory: 'basic',
    intentClarity: 'low',
    acceptableTools: ['suggest_options'],
    followUpPrompt: 'Create a beginner workout for me',
  },
  {
    id: 'OB06',
    category: 'onboarding',
    prompt: 'What can you do?',
    expectedTool: null,
    description: 'Capability question - should explain features without tool call',
    latencyCategory: 'basic',
    intentClarity: 'n/a',
    expectedTopics: ['workout', 'plan', 'track', 'schedule', 'exercise'],
  },
  {
    id: 'OB07',
    category: 'onboarding',
    prompt: 'Push day',
    expectedTool: 'create_workout',
    description: 'Shorthand request - should create push workout immediately',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'OB08',
    category: 'onboarding',
    prompt: 'Legs',
    expectedTool: null,
    description: 'Ambiguous single word - could be create workout OR ask what about legs',
    latencyCategory: 'basic',
    intentClarity: 'medium',
    acceptableTools: ['create_workout', 'suggest_options'],
    followUpPrompt: 'Create a leg workout',
  },

  // =========================================================================
  // MISSING TOOL COVERAGE TESTS (v253)
  // Cover the 4 tools not tested in v252: get_summary, analyze_training_data,
  // send_message, create_custom_workout
  // =========================================================================
  {
    id: 'MT01',
    category: 'tool_calling',
    prompt: 'How is my plan going?',
    expectedTool: 'get_summary',
    description: 'Progress query - should call get_summary',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, show me',
  },
  {
    id: 'MT02',
    category: 'tool_calling',
    prompt: 'Summarize my progress this week',
    expectedTool: 'get_summary',
    description: 'Explicit summary request - should call get_summary',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, summarize it',
  },
  {
    id: 'MT03',
    category: 'tool_calling',
    prompt: 'How has my bench press improved?',
    expectedTool: 'analyze_training_data',
    description: 'Historical analysis - should call analyze_training_data',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, analyze it',
  },
  {
    id: 'MT04',
    category: 'tool_calling',
    prompt: 'What are my strongest lifts?',
    expectedTool: 'analyze_training_data',
    description: 'Comparative analysis - should call analyze_training_data',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, show me',
  },
  {
    id: 'MT05',
    category: 'tool_calling',
    prompt: 'Am I making progress?',
    expectedTool: 'analyze_training_data',
    description: 'Progress analysis - should call analyze_training_data',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    acceptableTools: ['get_summary'],
    followUpPrompt: 'Yes, analyze my progress',
  },
  {
    id: 'MT06',
    category: 'tool_calling',
    prompt: 'Send a note to my trainer',
    expectedTool: null,
    description: 'Message without content - should ask what to send',
    latencyCategory: 'basic',
    intentClarity: 'low',
    acceptableTools: ['send_message'],
    followUpPrompt: 'Tell them I completed my workout',
  },
  {
    id: 'MT07',
    category: 'tool_calling',
    prompt: 'Tell my client great job on their workout today',
    expectedTool: 'send_message',
    description: 'Trainer sending message - should call send_message',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, send it',
  },
  {
    id: 'MT08',
    category: 'tool_calling',
    prompt: 'Create a workout with bench press, squats, and barbell rows',
    expectedTool: 'create_custom_workout',
    description: 'Explicit exercise list - should call create_custom_workout not create_workout',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    acceptableTools: ['create_workout'],
    followUpPrompt: 'Yes, create it',
  },

  // =========================================================================
  // TIER TESTING (v253)
  // Test prompt complexity for model tier routing decisions
  // =========================================================================
  {
    id: 'TT01',
    category: 'tier',
    prompt: 'Hi',
    expectedTool: null,
    description: 'Simple greeting - fast tier sufficient',
    latencyCategory: 'basic',
    intentClarity: 'n/a',
    tierRecommendation: 'fast',
  },
  {
    id: 'TT02',
    category: 'tier',
    prompt: 'Show schedule',
    expectedTool: 'show_schedule',
    description: 'Simple tool call - fast tier sufficient',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tierRecommendation: 'fast',
    followUpPrompt: 'Yes, show it',
  },
  {
    id: 'TT03',
    category: 'tier',
    prompt: 'Create push workout',
    expectedTool: 'create_workout',
    description: 'Standard tool call - standard tier',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tierRecommendation: 'standard',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'TT04',
    category: 'tier',
    prompt: 'Analyze my 3-month training progress and suggest what I should change to break through my plateau',
    expectedTool: 'analyze_training_data',
    description: 'Complex analysis + recommendations - smart tier needed',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tierRecommendation: 'smart',
    followUpPrompt: 'Yes, analyze it',
  },
  {
    id: 'TT05',
    category: 'tier',
    prompt: 'Design a 12-week periodized program for my first powerlifting meet, including peaking protocol',
    expectedTool: null,
    description: 'Complex multi-week planning - smart tier needed',
    latencyCategory: 'basic',
    intentClarity: 'low',
    tierRecommendation: 'smart',
    followUpPrompt: 'Yes, design it',
    acceptableTools: ['create_plan'],
  },
  {
    id: 'TT06',
    category: 'tier',
    prompt: 'Import this workout from the screenshot',
    expectedTool: null,
    description: 'Vision task placeholder - vision tier needed',
    latencyCategory: 'vision',
    intentClarity: 'high',
    tierRecommendation: 'vision',
    testType: 'vision',
    imageFixture: 'spreadsheet-screenshot.jpg',
    expectedExtractions: ['bench press', 'squat', 'deadlift'],
  },

  // =========================================================================
  // URL IMPORT TESTS (v253)
  // Test article/link import workflows with live URLs
  // =========================================================================
  {
    id: 'URL01',
    category: 'import',
    prompt: 'Create a plan from this article: https://www.t-nation.com/training/the-best-damn-workout-plan-for-natural-lifters/',
    expectedTool: null,
    description: 'T-Nation article import - should extract program structure',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'url_import',
    importUrl: 'https://www.t-nation.com/training/the-best-damn-workout-plan-for-natural-lifters/',
    expectedExtractions: ['push', 'pull', 'legs'],
  },
  {
    id: 'URL02',
    category: 'import',
    prompt: 'I want to follow this program: https://www.reddit.com/r/Fitness/wiki/recommended_routines/',
    expectedTool: null,
    description: 'Reddit wiki import - should extract program options',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'url_import',
    importUrl: 'https://www.reddit.com/r/Fitness/wiki/recommended_routines/',
    expectedExtractions: ['beginner', 'strength', 'muscle'],
  },
  {
    id: 'URL03',
    category: 'import',
    prompt: 'Use the workout from this video: https://www.youtube.com/watch?v=example',
    expectedTool: null,
    description: 'YouTube video import - should extract from description if possible',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'url_import',
    importUrl: 'https://www.youtube.com/watch?v=example',
    expectedTopics: ['video', 'workout'],
  },
  {
    id: 'URL04',
    category: 'import',
    prompt: 'Import from https://example.com/broken-link-404',
    expectedTool: null,
    description: 'Invalid URL - should handle gracefully',
    latencyCategory: 'basic',
    intentClarity: 'high',
    testType: 'url_import',
    importUrl: 'https://example.com/broken-link-404',
    expectedTopics: ['error', 'unable', 'access', 'try'],
  },
  {
    id: 'URL05',
    category: 'import',
    prompt: 'Import from https://www.nytimes.com/2024/01/01/technology/ai-news.html',
    expectedTool: null,
    description: 'Non-fitness URL - should politely decline',
    latencyCategory: 'basic',
    intentClarity: 'n/a',
    testType: 'url_import',
    importUrl: 'https://www.nytimes.com/2024/01/01/technology/ai-news.html',
    expectedTopics: ['fitness', 'workout', 'exercise'],
  },
  {
    id: 'URL06',
    category: 'import',
    prompt: 'I want her workout routine: https://www.instagram.com/p/example/',
    expectedTool: null,
    description: 'Instagram post - may have limited access but should try',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'url_import',
    importUrl: 'https://www.instagram.com/p/example/',
    expectedTopics: ['instagram', 'workout'],
  },

  // =========================================================================
  // VISION IMPORT TESTS (v253)
  // Test screenshot/photo import workflows - requires user-provided fixtures
  // =========================================================================
  {
    id: 'IM01',
    category: 'import',
    prompt: 'Import this workout log',
    expectedTool: null,
    description: 'Spreadsheet screenshot - should extract exercises and sets',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'spreadsheet-screenshot.jpg',
    expectedExtractions: ['bench press', 'squat'],
  },
  {
    id: 'IM02',
    category: 'import',
    prompt: 'Add these exercises to my history',
    expectedTool: null,
    description: 'Strong app screenshot - should extract and import workout',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'strong-app-screenshot.jpg',
    expectedExtractions: ['exercise'],
  },
  {
    id: 'IM03',
    category: 'import',
    prompt: 'Can you read my workout notes?',
    expectedTool: null,
    description: 'Handwritten log - should OCR and extract exercises',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'handwritten-log.jpg',
    expectedExtractions: ['exercise'],
  },
  {
    id: 'IM04',
    category: 'import',
    prompt: 'I want to try this workout',
    expectedTool: null,
    description: 'Instagram workout post - should extract program',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'instagram-post.jpg',
    expectedExtractions: ['exercise'],
  },
  {
    id: 'IM05',
    category: 'import',
    prompt: 'Save these PRs',
    expectedTool: null,
    description: 'Gym PR board photo - should extract 1RMs',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'pr-board.jpg',
    expectedExtractions: ['bench', 'squat', 'deadlift'],
  },
  {
    id: 'IM06',
    category: 'import',
    prompt: 'Import this',
    expectedTool: null,
    description: 'Blurry/low-quality photo - should handle gracefully with low confidence',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'blurry-image.jpg',
    expectedTopics: ['unclear', 'blurry', 'quality', 'try again'],
  },
  {
    id: 'IM07',
    category: 'import',
    prompt: 'Import this',
    expectedTool: null,
    description: 'Non-workout image (cat photo) - should politely decline',
    latencyCategory: 'vision',
    intentClarity: 'n/a',
    testType: 'vision',
    imageFixture: 'non-workout.jpg',
    expectedTopics: ['workout', 'exercise', 'fitness', 'image'],
  },
  {
    id: 'IM08',
    category: 'import',
    prompt: 'Log this set',
    expectedTool: null,
    description: 'Machine display photo - should extract weight/reps',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'machine-display.jpg',
    expectedExtractions: ['weight', 'reps'],
  },
  {
    id: 'IM09',
    category: 'import',
    prompt: 'Import my old program',
    expectedTool: null,
    description: 'TrueCoach screenshot - should extract full program',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'truecoach-screenshot.jpg',
    expectedExtractions: ['exercise', 'sets', 'reps'],
  },
  {
    id: 'IM10',
    category: 'import',
    prompt: 'Add all of these',
    expectedTool: null,
    description: 'Multiple exercises in one image - should batch extract',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'multiple-exercises.jpg',
    expectedExtractions: ['exercise'],
  },

  // =========================================================================
  // VISION IMPORT INTENT CLASSIFICATION TESTS (v259)
  // Test correct action detection: workout vs plan vs profile vs history
  // =========================================================================
  {
    id: 'VIS01',
    category: 'import',
    prompt: 'Import this workout',
    expectedTool: 'update_exercise_target',  // NOT create_workout - this is 1RM data
    description: '1RM spreadsheet should update targets, NOT create workout',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'bobby-1rm-max.png',
    expectedExtractions: ['squat', 'deadlift', 'bench', '220', '240', '200'],
  },
  {
    id: 'VIS02',
    category: 'import',
    prompt: 'Create a plan for my neurotype',
    expectedTool: 'create_plan',  // Neurotype 1B influences plan programming
    description: 'Neurotype 1B - create plan with explosive movements, variety, moderate volume',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'bobby-neurotype.png',
    expectedExtractions: ['neurotype', '1B', 'type'],
  },
  {
    id: 'VIS03',
    category: 'import',
    prompt: 'Import my workout history',
    expectedTool: null,  // Uses importCSV endpoint, not chat tool
    description: 'CSV historical workout import (24+ sessions)',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'mihir-history.csv',
    expectedExtractions: ['squat', 'deadlift', 'bench', 'overhead press'],
  },
  {
    id: 'VIS04',
    category: 'import',
    prompt: 'Create this workout plan for me',
    expectedTool: 'create_plan',  // Multiple workouts = PLAN, not single workout
    description: 'Multi-workout image (Push + Leg) should create PLAN not single workout',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'push-day-plan.png',
    expectedExtractions: ['push day', 'leg day', 'incline', 'squat', 'leg press'],
  },
  {
    id: 'VIS05',
    category: 'import',
    prompt: 'Create this workout for me',
    expectedTool: 'create_workout',  // Single workout - exact match
    description: 'Social media single workout - should match exercises exactly',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'social-media-workout.png',
    expectedExtractions: ['incline press', 'bench press', 'shoulder press', 'lateral raise', 'tricep dips', 'pushdowns'],
  },
  {
    id: 'VIS06',
    category: 'import',
    prompt: 'Import this workout',
    expectedTool: 'create_workout',  // Single workout from coaching app
    description: 'TrueCoach app workout with detailed protocols (RPE, tempo)',
    latencyCategory: 'vision',
    intentClarity: 'high',
    testType: 'vision',
    imageFixture: 'truecoach-workout.png',
    expectedExtractions: ['bench press', 'pendlay row', 'incline', 'seated row'],
  },
  {
    id: 'VIS07',
    category: 'import',
    prompt: 'Log this completed workout',
    expectedTool: null,  // Should ask if import history or create new
    description: 'Completed workout with weights - should clarify: log history or create new?',
    latencyCategory: 'vision',
    intentClarity: 'medium',
    testType: 'vision',
    imageFixture: 'truecoach-results.png',
    expectedExtractions: ['105', '95', '12', '9', '11', '10'],
  },
];

// Pricing per 1M tokens (as of Dec 2024)
export const TOKEN_PRICING = {
  'gpt-4o-mini': { input: 0.15, output: 0.60 },
  'gpt-4o': { input: 2.50, output: 10.00 },
  'claude-3.5-sonnet': { input: 3.00, output: 15.00 },
  'claude-3.5-haiku': { input: 0.80, output: 4.00 },
  'grok-2': { input: 2.00, output: 10.00 },
};

/**
 * Calculate cost for a request
 */
export function calculateCost(
  model: keyof typeof TOKEN_PRICING,
  inputTokens: number,
  outputTokens: number
): number {
  const pricing = TOKEN_PRICING[model];
  if (!pricing) return 0;

  const inputCost = (inputTokens / 1_000_000) * pricing.input;
  const outputCost = (outputTokens / 1_000_000) * pricing.output;

  return inputCost + outputCost;
}

/**
 * Get test cases by category
 */
export function getTestsByCategory(category: TestCase['category']): TestCase[] {
  return TEST_CASES.filter(t => t.category === category);
}

/**
 * v251: Get test cases by latency category
 */
export function getTestsByLatencyCategory(latencyCategory: TestCase['latencyCategory']): TestCase[] {
  return TEST_CASES.filter(t => t.latencyCategory === latencyCategory);
}

/**
 * Summary of test suite
 */
export function getTestSuiteSummary(): {
  total: number;
  byCategory: Record<string, number>;
  byLatencyCategory: Record<string, number>;
} {
  const byCategory: Record<string, number> = {};
  const byLatencyCategory: Record<string, number> = {};

  for (const test of TEST_CASES) {
    byCategory[test.category] = (byCategory[test.category] || 0) + 1;
    byLatencyCategory[test.latencyCategory] = (byLatencyCategory[test.latencyCategory] || 0) + 1;
  }

  return {
    total: TEST_CASES.length,
    byCategory,
    byLatencyCategory,
  };
}
