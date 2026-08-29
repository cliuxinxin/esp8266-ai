#include <cassert>

#include "auto_display_logic.h"

void testLegacyBridgeDefaults() {
  const AutoDisplayConfig config{};

  assert(!config.claudeEnabled);
  assert(config.codexEnabled);
  assert(config.approvalEnabled);
  assert(config.musicEnabled);

  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds == 10);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].intervalSeconds == 1800);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds == 12);
  assert(!config.scheduled[AUTO_SCHEDULED_STOCK].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_STOCK].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_STOCK].durationSeconds == 10);
  assert(!config.scheduled[AUTO_SCHEDULED_NET].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_NET].intervalSeconds == 600);
  assert(config.scheduled[AUTO_SCHEDULED_NET].durationSeconds == 10);
}

void testClaudeCanBeDisabled() {
  AutoSelectionInputs in{};
  in.claudeWorking = true;
  in.config.claudeEnabled = false;
  assert(chooseAutoDisplay(in) == AUTO_IDLE);

  in.config.claudeEnabled = true;
  assert(chooseAutoDisplay(in) == AUTO_CLAUDE);
}

void testApprovalsCanBeDisabled() {
  AutoSelectionInputs in{};
  in.approvalNeeded = true;
  in.config.approvalEnabled = false;
  assert(chooseAutoDisplay(in) == AUTO_IDLE);

  in.config.approvalEnabled = true;
  assert(chooseAutoDisplay(in) == AUTO_APPROVAL);
}

void testPriorityAndFairScheduledChoice() {
  AutoSelectionInputs in{};
  in.config.codexEnabled = true;
  in.codexWorking = true;
  in.musicPlaying = true;
  assert(chooseAutoDisplay(in) == AUTO_CODEX);

  in.codexWorking = false;
  assert(chooseAutoDisplay(in) == AUTO_MUSIC);

  in.musicPlaying = false;
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.validMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.lastShownWeather = 200;
  in.lastShownQuote = 100;
  assert(chooseAutoDisplay(in) == AUTO_QUOTE);

  in.approvalNeeded = true;
  assert(chooseAutoDisplay(in) == AUTO_APPROVAL);
}

void testAllItemsCanBeDisabled() {
  AutoSelectionInputs in{};
  in.config.claudeEnabled = false;
  in.config.codexEnabled = false;
  in.config.approvalEnabled = false;
  in.config.musicEnabled = false;
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) in.config.scheduled[i].enabled = false;
  in.approvalNeeded = true;
  in.claudeWorking = true;
  in.codexWorking = true;
  in.musicPlaying = true;
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE | AUTO_DUE_STOCK | AUTO_DUE_NET;
  in.validMask = in.dueMask;

  assert(chooseAutoDisplay(in) == AUTO_IDLE);
}

void testScheduledValidityMasks() {
  AutoSelectionInputs in{};
  in.dueMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.validMask = AUTO_DUE_QUOTE;
  assert(chooseAutoDisplay(in) == AUTO_QUOTE);

  in.validMask = 0;
  assert(chooseAutoDisplay(in) == AUTO_IDLE);

  in.validMask = AUTO_DUE_WEATHER | AUTO_DUE_QUOTE;
  in.config.scheduled[AUTO_SCHEDULED_QUOTE].enabled = false;
  assert(chooseAutoDisplay(in) == AUTO_WEATHER);
}

void testInvalidRangesAreClampedWithoutMutatingInput() {
  AutoDisplayConfig input{};
  input.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds = -20;
  input.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds = 999;
  input.scheduled[AUTO_SCHEDULED_QUOTE].intervalSeconds = 20000;
  input.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds = 1;

  const AutoDisplayConfig normalized = normalizeAutoDisplayConfig(input);

  assert(normalized.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 60);
  assert(normalized.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds == 60);
  assert(normalized.scheduled[AUTO_SCHEDULED_QUOTE].intervalSeconds == 14400);
  assert(normalized.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds == 5);
  assert(input.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == -20);
}

void testMissingPatchFieldsUseDefaults() {
  AutoDisplayConfigPatch patch{};
  patch.claudeEnabled = AutoConfigField<bool>{true, true};
  patch.scheduled[AUTO_SCHEDULED_WEATHER].enabled = AutoConfigField<bool>{true, false};

  const AutoDisplayConfig config = applyAutoDisplayConfigPatch(patch);

  assert(config.claudeEnabled);
  assert(config.codexEnabled);
  assert(config.musicEnabled);
  assert(!config.scheduled[AUTO_SCHEDULED_WEATHER].enabled);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_QUOTE].durationSeconds == 12);
}

void testInvalidPatchFieldsUseDefaults() {
  AutoDisplayConfigPatch patch{};
  patch.musicEnabled = AutoConfigField<bool>{false, false};
  patch.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds = AutoConfigField<int>{false, 1};
  patch.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds = AutoConfigField<int>{true, 2};

  const AutoDisplayConfig config = applyAutoDisplayConfigPatch(patch);

  assert(config.musicEnabled);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].intervalSeconds == 900);
  assert(config.scheduled[AUTO_SCHEDULED_WEATHER].durationSeconds == 5);
}

void testRepeatedRevisionIsIgnored() {
  AutoDisplayRuntimeState runtime{};
  AutoDisplayConfigPatch first{};
  first.codexEnabled = AutoConfigField<bool>{true, false};
  assert(applyAutoDisplayRevision(runtime, 7, first));
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs = 1234;

  AutoDisplayConfigPatch repeated{};
  repeated.codexEnabled = AutoConfigField<bool>{true, true};
  assert(!applyAutoDisplayRevision(runtime, 7, repeated));

  assert(!runtime.config.codexEnabled);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1234);
}

void testInterruptedPageRestartsWithFullDuration() {
  AutoDisplayRuntimeState runtime{};
  runtime.activeScheduledPage = AUTO_SCHEDULED_WEATHER;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs = 1000;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs = 6000;

  AutoTransitionInputs input{};
  input.nowMs = 2000;
  input.validMask = AUTO_DUE_WEATHER;
  input.approvalNeeded = true;
  assert(advanceAutoDisplay(runtime, input) == AUTO_APPROVAL);
  assert(runtime.activeScheduledPage == AUTO_SCHEDULED_WEATHER);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1000);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 0);

  input.nowMs = 3000;
  input.approvalNeeded = false;
  assert(advanceAutoDisplay(runtime, input) == AUTO_WEATHER);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1000);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 13000);
}

void testFixedModeDoesNotRunAutoScheduler() {
  AutoDisplayRuntimeState runtime{};
  runtime.activeScheduledPage = AUTO_SCHEDULED_WEATHER;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs = 1000;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs = 6000;
  runtime.scheduled[AUTO_SCHEDULED_WEATHER].lastShownOrder = 3;
  runtime.lastShownOrder = 3;

  AutoTransitionInputs input{};
  input.autoMode = false;
  input.nowMs = 7000;
  input.validMask = AUTO_DUE_WEATHER;
  input.approvalNeeded = true;

  assert(advanceAutoDisplay(runtime, input) == AUTO_IDLE);
  assert(runtime.activeScheduledPage == AUTO_SCHEDULED_WEATHER);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].dueMs == 1000);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].untilMs == 6000);
  assert(runtime.scheduled[AUTO_SCHEDULED_WEATHER].lastShownOrder == 3);
  assert(runtime.lastShownOrder == 3);
}

int main() {
  testLegacyBridgeDefaults();
  testClaudeCanBeDisabled();
  testApprovalsCanBeDisabled();
  testPriorityAndFairScheduledChoice();
  testAllItemsCanBeDisabled();
  testScheduledValidityMasks();
  testInvalidRangesAreClampedWithoutMutatingInput();
  testMissingPatchFieldsUseDefaults();
  testInvalidPatchFieldsUseDefaults();
  testRepeatedRevisionIsIgnored();
  testInterruptedPageRestartsWithFullDuration();
  testFixedModeDoesNotRunAutoScheduler();
  return 0;
}
