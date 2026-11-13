#import <Foundation/Foundation.h>

typedef void (^CTBTouchBarProbeResult)(BOOL appControlsAreEmpty);

// Samples only the Touch Bar for a short time. Unavailable or dark samples yield to the active app.
void CTBProbeTouchBar(void *framework, CTBTouchBarProbeResult result);
