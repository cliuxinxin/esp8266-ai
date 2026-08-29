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
