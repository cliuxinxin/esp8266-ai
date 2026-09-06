#pragma once

struct NowPageRevision {
  int content = -1;
  int layout = -1;
};

inline bool nowPageRevisionChanged(bool valid, const NowPageRevision &current,
                                   const NowPageRevision &incoming) {
  return !valid || current.content != incoming.content || current.layout != incoming.layout;
}

inline bool nowPageFrameIsCurrent(bool screenDrawn, const NowPageRevision &drawn,
                                  const NowPageRevision &current, bool dirty) {
  return screenDrawn && !dirty && !nowPageRevisionChanged(true, drawn, current);
}
