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
  category: 'tool_calling' | 'fitness_accuracy' | 'tone' | 'speed' | 'onboarding' | 'import' | 'tier' | 'protocol_accuracy';
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
  unacceptableTools?: string[];            // v264: Tools that would be WRONG for this test
  edgeCase?: boolean;                      // v264: Flag for human review attention

  // v253: Multimodal support
  testType?: 'text' | 'vision' | 'url_import';  // Default: 'text'
  imageFixture?: string;                   // Filename in fixtures/ directory (for vision tests)
  importUrl?: string;                      // URL to fetch and import (for url_import tests)
  expectedExtractions?: string[];          // Expected exercise names from vision/url extraction
  tierRecommendation?: 'fast' | 'standard' | 'smart' | 'vision';  // For tier tests

  // v260: Protocol accuracy tests
  expectedProtocol?: string;               // Expected protocolId for protocol_accuracy tests
  expectedExerciseIds?: string[];          // Expected exercise IDs for exercise accuracy tests

  // v263: Split type accuracy tests
  expectedSplitType?: string;              // Expected splitType for vision import tests (e.g., 'pushLegs', 'pushPullLegs')

  // v265: Test tier classification
  // Tier 1 (Core): Uses Medina terminology, must execute correctly
  // Tier 2 (Interpretation): Clear intent but varied language, execute OR clarify OK
  // Tier 3 (Ambiguous): Unclear intent, clarification preferred
  tier?: 1 | 2 | 3;

  // v266: Output quality constraints - validate the OUTPUT is correct, not just tool called
  expectedConstraints?: {
    duration?: number;           // Expected workout duration in minutes
    durationTolerance?: number;  // ±N min tolerance (default: 15)
    splitType?: string;          // 'upper', 'lower', 'push', 'pull', 'full', 'legs'
    protocol?: string;           // 'GBC', '5x5', 'rest_pause'
    equipment?: string[];        // ['barbell', 'dumbbells', 'bodyweight']
    exerciseCount?: number;      // Expected number of exercises
    exercises?: string[];        // Specific exercises that must be included
    date?: string;               // 'tomorrow', 'today', 'monday'
  };
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
    edgeCase: true,  // v264: Ask first vs execute - both defensible
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
    edgeCase: true,  // v264: Preference vs command - ask or execute both defensible
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
    expectedTool: null,  // No strong expectation - multiple valid approaches
    acceptableTools: ['show_schedule', 'get_summary'],  // v264: Showing schedule is helpful, not wrong
    maxResponseTime: 2500,
    description: 'Simple question about schedule - text answer OR show_schedule both valid',
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
    acceptableTools: ['delete_plan', 'abandon_plan'],  // v264: Either tool valid for "delete" intent
    unacceptableTools: ['create_plan', 'activate_plan'],  // v264: Wrong direction
    edgeCase: true,  // v264: Business rule - which delete tool is "right"?
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
    description: 'Vague command - AI should ask for details, then create workout',
    latencyCategory: 'tool_call',
    intentClarity: 'low',  // v266: Vague command, asking for clarification is appropriate
    tier: 2,  // v266: Clarification acceptable, not a Tier 1 "must pass immediately"
    followUpPrompt: 'Upper body, 45 minutes',  // v266: Meaningful follow-up with actual details
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
    edgeCase: true,  // v264: Genuinely ambiguous - requires human judgment
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
    expectedTool: 'update_exercise_target',
    description: 'Vision task - 1RM spreadsheet should update targets',
    latencyCategory: 'vision',
    intentClarity: 'high',
    tierRecommendation: 'vision',
    testType: 'vision',
    imageFixture: 'bobby-1rm-max.png',
    expectedExtractions: ['squat', 'deadlift', 'bench'],
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
    // v263: Split type accuracy - DEFERRED (system only supports 5 hardcoded splits)
    // expectedSplitType: 'pushLegs',  // Would need custom split support to pass
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

  // =========================================================================
  // PROTOCOL ACCURACY TESTS (v260)
  // Test that AI passes correct protocol when user specifies training style
  // =========================================================================
  {
    id: 'PROT01',
    category: 'protocol_accuracy',
    prompt: 'Create a plan using GBC protocol',
    expectedTool: 'create_plan',
    expectedProtocol: 'gbc_relative_compound',
    description: 'GBC request should pass gbc_relative_compound protocolId',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
    expectedTopics: ['GBC', 'German Body', '12', '30'],
  },
  {
    id: 'PROT02',
    category: 'protocol_accuracy',
    prompt: 'Make me an 8 week hypertrophy program with drop sets',
    expectedTool: 'create_plan',
    expectedProtocol: 'drop_set',
    description: 'Drop set request should pass drop_set protocolId',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'PROT03',
    category: 'protocol_accuracy',
    prompt: 'Create a strength plan with 5x5',
    expectedTool: 'create_plan',
    expectedProtocol: 'strength_5x5_compound',
    description: '5x5 request should pass strength_5x5_compound protocolId',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
    expectedTopics: ['5x5', '5', 'sets', 'strength'],
  },
  {
    id: 'PROT04',
    category: 'protocol_accuracy',
    prompt: 'Create a workout with German Body Comp training',
    expectedTool: 'create_workout',
    expectedProtocol: 'gbc_relative_compound',
    description: 'GBC workout should pass gbc_relative_compound protocolId',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },
  {
    id: 'PROT05',
    category: 'protocol_accuracy',
    prompt: 'Build me a plan with rest-pause training',
    expectedTool: 'create_plan',
    expectedProtocol: 'rest_pause',
    description: 'Rest-pause request should pass rest_pause protocolId',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
    expectedTopics: ['rest', 'pause'],
  },
  {
    id: 'PROT06',
    category: 'protocol_accuracy',
    prompt: 'Create a plan with bench press, squats, and deadlifts',
    expectedTool: 'create_plan',
    expectedExerciseIds: ['barbell_bench_press', 'barbell_back_squat', 'barbell_deadlift'],
    description: 'Explicit exercises should be passed via exerciseIds',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    followUpPrompt: 'Yes, create it',
  },

  // =========================================================================
  // WORKOUT QUALITY TESTS (v266)
  // Test that AI creates workouts with CORRECT constraints, not just calls tool
  // These validate OUTPUT quality, not just tool invocation
  // =========================================================================
  {
    id: 'WQ01',
    category: 'tool_calling',
    prompt: 'Create a 45-minute upper body workout for tomorrow using GBC protocol',
    expectedTool: 'create_workout',
    description: 'Full constraint workout - duration, split, protocol, date',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      duration: 45,
      durationTolerance: 10,
      splitType: 'upper',
      protocol: 'gbc',
      date: 'tomorrow',
    },
  },
  {
    id: 'WQ02',
    category: 'tool_calling',
    prompt: 'Create a 60-minute home workout with only bodyweight exercises',
    expectedTool: 'create_workout',
    description: 'Home workout with equipment constraints',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      duration: 60,
      durationTolerance: 15,
      equipment: ['bodyweight'],
    },
  },
  {
    id: 'WQ03',
    category: 'tool_calling',
    prompt: 'Create a push workout with bench press, overhead press, and dips',
    expectedTool: 'create_workout',
    description: 'Push workout with specific exercises',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      splitType: 'push',
      exercises: ['bench_press', 'overhead_press', 'dips'],
    },
  },
  {
    id: 'WQ04',
    category: 'tool_calling',
    prompt: 'Create a 30-minute lower body workout',
    expectedTool: 'create_workout',
    description: 'Lower body workout with duration',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      duration: 30,
      durationTolerance: 10,
      splitType: 'lower',
    },
  },
  {
    id: 'WQ05',
    category: 'tool_calling',
    prompt: 'Create a leg workout for today',
    expectedTool: 'create_workout',
    description: 'Leg workout with date',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      splitType: 'legs',
      date: 'today',
    },
  },
  {
    id: 'WQ06',
    category: 'tool_calling',
    prompt: 'Create a quick 20-minute full body workout',
    expectedTool: 'create_workout',
    description: 'Short full body workout',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      duration: 20,
      durationTolerance: 5,
      splitType: 'full',
    },
  },
  {
    id: 'WQ07',
    category: 'tool_calling',
    prompt: 'Create a full body workout with dumbbells only',
    expectedTool: 'create_workout',
    description: 'Full body with dumbbell constraints',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      splitType: 'full',
      equipment: ['dumbbells', 'dumbbell'],
    },
  },
  {
    id: 'WQ08',
    category: 'tool_calling',
    prompt: 'Create a pull workout with heavy barbell rows',
    expectedTool: 'create_workout',
    description: 'Pull workout with specific exercise',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      splitType: 'pull',
      exercises: ['barbell_row', 'row'],
    },
  },
  {
    id: 'WQ09',
    category: 'tool_calling',
    prompt: 'Create a 45-minute workout from home with light dumbbells',
    expectedTool: 'create_workout',
    description: 'Home workout with duration and equipment',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      duration: 45,
      durationTolerance: 15,
      equipment: ['dumbbells', 'dumbbell', 'bodyweight'],
    },
  },
  {
    id: 'WQ10',
    category: 'tool_calling',
    prompt: 'Create an upper body workout with 5x5 strength focus',
    expectedTool: 'create_workout',
    description: 'Upper body with 5x5 protocol',
    latencyCategory: 'tool_call',
    intentClarity: 'high',
    tier: 1,
    followUpPrompt: 'Yes, create it',
    expectedConstraints: {
      splitType: 'upper',
      protocol: '5x5',
    },
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

/**
 * v265: Assign tier to a test based on prompt heuristics
 *
 * Tier 1 (Core): Uses Medina terminology explicitly
 * Tier 2 (Interpretation): Clear intent but varied/colloquial language
 * Tier 3 (Ambiguous): Genuinely unclear intent
 */
export function assignTier(test: TestCase): 1 | 2 | 3 {
  // If tier is explicitly set, use it
  if (test.tier) return test.tier;

  const prompt = test.prompt.toLowerCase();

  // Tier 1 patterns: Medina terminology with clear action verbs
  const tier1Patterns = [
    /create\s+(a\s+)?(push|pull|leg|upper|lower|full.body)?\s*workout/,
    /create\s+(a\s+)?\d+.week\s+plan/,
    /show\s+(my\s+)?schedule/,
    /add\s+.+\s+to\s+(my\s+)?library/,
    /update\s+(my\s+)?profile/,
    /skip\s+(today.s\s+)?workout/,
    /delete\s+(my\s+)?plan/,
    /activate\s+(this\s+)?plan/,
    /analyze\s+(my\s+)?(progress|training)/,
  ];

  // Tier 3 patterns: Genuinely ambiguous (single words, statements, vague)
  const tier3Patterns = [
    /^(legs?|push|pull|chest|back|arms?|shoulders?|core)$/i,  // Single body part
    /^(5x5|gbc|ppl|bro.split)$/i,  // Protocol abbreviations alone
    /^i('m|.am)\s+\d+\s+(years?\s+old|lbs?|kg)/,  // Age/weight statements
    /^i\s+want\s+to\s+(train|workout|lift)/,  // Preference statements
    /^(give|get)\s+me\s+(a\s+)?(something|workout)/,  // Vague requests
    /^help\s+me\s+(start|begin)/,  // Onboarding vague
  ];

  // Check Tier 1 first (most specific)
  for (const pattern of tier1Patterns) {
    if (pattern.test(prompt)) return 1;
  }

  // Check Tier 3 (ambiguous)
  for (const pattern of tier3Patterns) {
    if (pattern.test(prompt)) return 3;
  }

  // Check for knowledge questions (Tier 1 - no tool expected)
  if (test.intentClarity === 'n/a') return 1;

  // Check for fitness accuracy tests (Tier 1 - knowledge validation)
  if (test.category === 'fitness_accuracy' || test.category === 'tone') return 1;

  // Tier 2: Everything else (clear intent but varied language)
  // Includes: "program", "routine", protocol names without explicit plan/workout
  return 2;
}

/**
 * v265: Get test cases by tier
 */
export function getTestsByTier(tier: 1 | 2 | 3): TestCase[] {
  return TEST_CASES.filter(t => assignTier(t) === tier);
}

/**
 * v265: Get tier summary
 */
export function getTierSummary(): { tier1: number; tier2: number; tier3: number } {
  let tier1 = 0, tier2 = 0, tier3 = 0;
  for (const test of TEST_CASES) {
    const tier = assignTier(test);
    if (tier === 1) tier1++;
    else if (tier === 2) tier2++;
    else tier3++;
  }
  return { tier1, tier2, tier3 };
}
