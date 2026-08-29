#pragma once

#include <cstdint>

enum AutoScheduledPage {
  AUTO_SCHEDULED_WEATHER,
  AUTO_SCHEDULED_QUOTE,
  AUTO_SCHEDULED_STOCK,
  AUTO_SCHEDULED_NET,
  AUTO_SCHEDULED_COUNT,
};

enum AutoDisplayChoice {
  AUTO_IDLE,
  AUTO_APPROVAL,
  AUTO_CLAUDE,
  AUTO_CODEX,
  AUTO_MUSIC,
  AUTO_WEATHER,
  AUTO_QUOTE,
  AUTO_STOCK,
  AUTO_NET,
};

enum AutoDueMask : uint8_t {
  AUTO_DUE_WEATHER = 1U << AUTO_SCHEDULED_WEATHER,
  AUTO_DUE_QUOTE = 1U << AUTO_SCHEDULED_QUOTE,
  AUTO_DUE_STOCK = 1U << AUTO_SCHEDULED_STOCK,
  AUTO_DUE_NET = 1U << AUTO_SCHEDULED_NET,
};

struct AutoScheduledSetting {
  bool enabled;
  int intervalSeconds;
  int durationSeconds;
};

struct AutoDisplayConfig {
  bool claudeEnabled = false;
  bool codexEnabled = true;
  bool approvalEnabled = true;
  bool musicEnabled = true;
  AutoScheduledSetting scheduled[AUTO_SCHEDULED_COUNT] = {
      {true, 900, 10},
      {true, 1800, 12},
      {false, 900, 10},
      {false, 600, 10},
  };
};

struct ScheduledPageState {
  uint32_t dueMs = 0;
  uint32_t untilMs = 0;
  uint32_t lastShownOrder = 0;
};

template <typename T>
struct AutoConfigField {
  bool valid = false;
  T value{};
};

struct AutoScheduledConfigPatch {
  AutoConfigField<bool> enabled{};
  AutoConfigField<int> intervalSeconds{};
  AutoConfigField<int> durationSeconds{};
};

struct AutoDisplayConfigPatch {
  AutoConfigField<bool> claudeEnabled{};
  AutoConfigField<bool> codexEnabled{};
  AutoConfigField<bool> approvalEnabled{};
  AutoConfigField<bool> musicEnabled{};
  AutoScheduledConfigPatch scheduled[AUTO_SCHEDULED_COUNT]{};
};

struct AutoDisplayRuntimeState {
  AutoDisplayConfig config{};
  int revision = -1;
  ScheduledPageState scheduled[AUTO_SCHEDULED_COUNT]{};
  int activeScheduledPage = -1;
  uint32_t lastShownOrder = 0;
};

struct AutoSelectionInputs {
  AutoDisplayConfig config{};
  bool approvalNeeded = false;
  bool claudeWorking = false;
  bool codexWorking = false;
  bool musicPlaying = false;
  uint8_t dueMask = 0;
  uint8_t validMask = 0;
  uint32_t lastShownWeather = 0;
  uint32_t lastShownQuote = 0;
  uint32_t lastShownStock = 0;
  uint32_t lastShownNet = 0;
};

struct AutoTransitionInputs {
  bool autoMode = true;
  uint32_t nowMs = 0;
  bool approvalNeeded = false;
  bool claudeWorking = false;
  bool codexWorking = false;
  bool musicPlaying = false;
  uint8_t validMask = 0;
};

inline int clampAutoSeconds(int value, int lower, int upper) {
  if (value < lower) return lower;
  if (value > upper) return upper;
  return value;
}

inline AutoDisplayConfig normalizeAutoDisplayConfig(const AutoDisplayConfig &input) {
  AutoDisplayConfig result = input;
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) {
    result.scheduled[i].intervalSeconds = clampAutoSeconds(result.scheduled[i].intervalSeconds, 60, 14400);
    result.scheduled[i].durationSeconds = clampAutoSeconds(result.scheduled[i].durationSeconds, 5, 60);
  }
  return result;
}

inline AutoDisplayConfig applyAutoDisplayConfigPatch(const AutoDisplayConfigPatch &patch) {
  AutoDisplayConfig result;
  if (patch.claudeEnabled.valid) result.claudeEnabled = patch.claudeEnabled.value;
  if (patch.codexEnabled.valid) result.codexEnabled = patch.codexEnabled.value;
  if (patch.approvalEnabled.valid) result.approvalEnabled = patch.approvalEnabled.value;
  if (patch.musicEnabled.valid) result.musicEnabled = patch.musicEnabled.value;
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) {
    const AutoScheduledConfigPatch &setting = patch.scheduled[i];
    if (setting.enabled.valid) result.scheduled[i].enabled = setting.enabled.value;
    if (setting.intervalSeconds.valid) result.scheduled[i].intervalSeconds = setting.intervalSeconds.value;
    if (setting.durationSeconds.valid) result.scheduled[i].durationSeconds = setting.durationSeconds.value;
  }
  return normalizeAutoDisplayConfig(result);
}

inline void resetAutoDisplaySchedule(AutoDisplayRuntimeState &runtime) {
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) runtime.scheduled[i] = ScheduledPageState{};
  runtime.activeScheduledPage = -1;
  runtime.lastShownOrder = 0;
}

inline bool applyAutoDisplayRevision(AutoDisplayRuntimeState &runtime, int revision,
                                     const AutoDisplayConfigPatch &patch) {
  if (revision == runtime.revision) return false;
  runtime.config = applyAutoDisplayConfigPatch(patch);
  runtime.revision = revision;
  resetAutoDisplaySchedule(runtime);
  return true;
}

inline uint8_t autoDueBitForScheduledPage(int index) {
  return static_cast<uint8_t>(1U << index);
}

inline uint32_t autoLastShownForScheduledPage(const AutoSelectionInputs &input, int index) {
  if (index == AUTO_SCHEDULED_WEATHER) return input.lastShownWeather;
  if (index == AUTO_SCHEDULED_QUOTE) return input.lastShownQuote;
  if (index == AUTO_SCHEDULED_STOCK) return input.lastShownStock;
  return input.lastShownNet;
}

inline AutoDisplayChoice autoChoiceForScheduledPage(int index) {
  if (index == AUTO_SCHEDULED_WEATHER) return AUTO_WEATHER;
  if (index == AUTO_SCHEDULED_QUOTE) return AUTO_QUOTE;
  if (index == AUTO_SCHEDULED_STOCK) return AUTO_STOCK;
  return AUTO_NET;
}

inline AutoDisplayChoice chooseAutoDisplay(const AutoSelectionInputs &input) {
  if (input.config.approvalEnabled && input.approvalNeeded) return AUTO_APPROVAL;
  if (input.config.codexEnabled && input.codexWorking) return AUTO_CODEX;
  if (input.config.claudeEnabled && input.claudeWorking) return AUTO_CLAUDE;
  if (input.config.musicEnabled && input.musicPlaying) return AUTO_MUSIC;

  AutoDisplayChoice best = AUTO_IDLE;
  uint32_t oldest = 0;
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) {
    const uint8_t bit = autoDueBitForScheduledPage(i);
    if (!input.config.scheduled[i].enabled || !(input.dueMask & bit) || !(input.validMask & bit)) continue;
    const uint32_t lastShown = autoLastShownForScheduledPage(input, i);
    if (best == AUTO_IDLE || lastShown < oldest) {
      best = autoChoiceForScheduledPage(i);
      oldest = lastShown;
    }
  }
  return best;
}

inline bool autoDeadlineReached(uint32_t nowMs, uint32_t deadlineMs) {
  return deadlineMs != 0 && static_cast<int32_t>(nowMs - deadlineMs) >= 0;
}

inline uint32_t autoMilliseconds(int seconds) {
  return static_cast<uint32_t>(seconds) * 1000U;
}

inline AutoSelectionInputs autoSelectionInputsForTransition(const AutoDisplayRuntimeState &runtime,
                                                            const AutoTransitionInputs &transition,
                                                            uint8_t dueMask = 0) {
  AutoSelectionInputs input;
  input.config = runtime.config;
  input.approvalNeeded = transition.approvalNeeded;
  input.claudeWorking = transition.claudeWorking;
  input.codexWorking = transition.codexWorking;
  input.musicPlaying = transition.musicPlaying;
  input.validMask = transition.validMask;
  input.dueMask = dueMask;
  input.lastShownWeather = runtime.scheduled[AUTO_SCHEDULED_WEATHER].lastShownOrder;
  input.lastShownQuote = runtime.scheduled[AUTO_SCHEDULED_QUOTE].lastShownOrder;
  input.lastShownStock = runtime.scheduled[AUTO_SCHEDULED_STOCK].lastShownOrder;
  input.lastShownNet = runtime.scheduled[AUTO_SCHEDULED_NET].lastShownOrder;
  return input;
}

inline int scheduledPageForAutoChoice(AutoDisplayChoice choice) {
  if (choice == AUTO_WEATHER) return AUTO_SCHEDULED_WEATHER;
  if (choice == AUTO_QUOTE) return AUTO_SCHEDULED_QUOTE;
  if (choice == AUTO_STOCK) return AUTO_SCHEDULED_STOCK;
  if (choice == AUTO_NET) return AUTO_SCHEDULED_NET;
  return -1;
}

inline AutoDisplayChoice advanceAutoDisplay(AutoDisplayRuntimeState &runtime,
                                            const AutoTransitionInputs &input) {
  if (!input.autoMode) return AUTO_IDLE;

  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) {
    const uint8_t bit = autoDueBitForScheduledPage(i);
    if (runtime.config.scheduled[i].enabled && (input.validMask & bit) && runtime.scheduled[i].dueMs == 0) {
      runtime.scheduled[i].dueMs =
          input.nowMs + autoMilliseconds(runtime.config.scheduled[i].intervalSeconds);
    }
  }

  if (runtime.activeScheduledPage < -1 || runtime.activeScheduledPage >= AUTO_SCHEDULED_COUNT) {
    runtime.activeScheduledPage = -1;
  }
  if (runtime.activeScheduledPage >= 0) {
    ScheduledPageState &active = runtime.scheduled[runtime.activeScheduledPage];
    if (active.untilMs != 0 && autoDeadlineReached(input.nowMs, active.untilMs)) {
      active.untilMs = 0;
      active.dueMs = input.nowMs +
                     autoMilliseconds(runtime.config.scheduled[runtime.activeScheduledPage].intervalSeconds);
      runtime.activeScheduledPage = -1;
    }
  }

  const AutoDisplayChoice eventChoice =
      chooseAutoDisplay(autoSelectionInputsForTransition(runtime, input));
  if (eventChoice == AUTO_APPROVAL || eventChoice == AUTO_CLAUDE || eventChoice == AUTO_CODEX ||
      eventChoice == AUTO_MUSIC) {
    if (runtime.activeScheduledPage >= 0) {
      runtime.scheduled[runtime.activeScheduledPage].untilMs = 0;
    }
    return eventChoice;
  }

  if (runtime.activeScheduledPage >= 0) {
    const int page = runtime.activeScheduledPage;
    const uint8_t activeBit = autoDueBitForScheduledPage(page);
    if (runtime.config.scheduled[page].enabled && (input.validMask & activeBit)) {
      ScheduledPageState &active = runtime.scheduled[page];
      if (active.untilMs == 0) {
        active.untilMs = input.nowMs + autoMilliseconds(runtime.config.scheduled[page].durationSeconds);
        active.lastShownOrder = ++runtime.lastShownOrder;
      }
      return autoChoiceForScheduledPage(page);
    }
    runtime.scheduled[page].untilMs = 0;
    runtime.activeScheduledPage = -1;
  }

  uint8_t dueMask = 0;
  for (int i = 0; i < AUTO_SCHEDULED_COUNT; ++i) {
    if (autoDeadlineReached(input.nowMs, runtime.scheduled[i].dueMs)) {
      dueMask |= autoDueBitForScheduledPage(i);
    }
  }
  const AutoDisplayChoice scheduledChoice =
      chooseAutoDisplay(autoSelectionInputsForTransition(runtime, input, dueMask));
  const int selectedPage = scheduledPageForAutoChoice(scheduledChoice);
  if (selectedPage >= 0) {
    runtime.activeScheduledPage = selectedPage;
    ScheduledPageState &selected = runtime.scheduled[selectedPage];
    selected.untilMs = input.nowMs + autoMilliseconds(runtime.config.scheduled[selectedPage].durationSeconds);
    selected.lastShownOrder = ++runtime.lastShownOrder;
  }
  return scheduledChoice;
}
