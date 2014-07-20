library dining_philosophers.sleep;

import "dart:async";
import "dart:math";

var _random = new Random();

/// completes after [delay] ms with value null
Future sleep(delay) =>
    new Future.delayed(new Duration(milliseconds: delay), () => null);

/// completes after a random number of `ms` in the range
/// 0..[range] with value null
Future sleepRandom(range) => sleep(_random.nextInt(range));
