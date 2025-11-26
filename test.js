// Simple failing test for demonstration
function assertEqual(a, b, message) {
  if (a !== b) {
    throw new Error(`Assertion failed: ${message} | ${a} !== ${b}`);
  }
}

// This test will FAIL intentionally to trigger n8n AI
assertEqual(1 + 1, 3, "AI should detect and fix this test");

