library dining_philosophers.dinner3;
/**
 * This version of a dinner of philosophers consists of the following
 * actors:
 *
 * 1 _n_ actors running for [Chopstick]s
 * 2 _n_ actors running individual [Philosopher]s
 *
 * A [Chopstick] actor controls access to an individual chopstick.
 *
 * A [Philosopher] knows its left and right chopsticks. Before it starts
 * to eat, it tries to acquire them by sending a [GrabChopstick] message
 * to them.
 *
 * [Philosopher]s use *polling*. If a philosopher fails to acquire both
 * chopsticks, it release the already acquired ones and retries later.
 *
 */


import "dart:isolate";
import "dart:math";
import "dart:async";

var _random = new Random();

/// completes after [delay] ms with value null
Future _sleep(delay) => new Future.delayed(
    new Duration(milliseconds:delay), ()=>null);

/// completes after a random number of `ms` in the range
/// 0..[range] with value null
Future _sleepRandom(range) => _sleep(_random.nextInt(range));

/**
 * The table where the dinner takes place.
 *
 * An instance of Table prepares the required [Chopstick]s,
 * places the [Philosopher]s and provides a method to start
 * the dinner.
 *
 * A table doesn't participate in controlling concurrent access
 * to chopsticks.
 */
class Table {
  var _chopsticks = [];
  var _philosophers = [];
  int _n;

  Table(this._n) {
    assert(_n >= 2);
    _prepareTable();
    _placePhilosophers();
  }

  _prepareTable() {
    for (int i=0; i<_n; i++) {
      var cs = spawnFunction(chopstick);
      cs.send(new InitChopstick(i));
      _chopsticks.add(cs);
    }
  }

  _placePhilosophers() {
    for (int i=0; i< _n; i++) {
      var p = spawnFunction(philosopher);
      var l = i;
      var r = (i + _n -1) % _n;
      p.send(new InitPhilosopher(i, _chopsticks[l], _chopsticks[r]));
      _philosophers.add(p);
    }
  }

  dine() => _philosophers.forEach((p) => p.send(new StartDinner()));
}

/// message sent to a chopstick to initialize it
class InitChopstick {
  /// the chopstick id
  final int id;
  InitChopstick(this.id);
}

/// message sent to a chopstick to grab it
class GrabChopstick {
  final int philosopher;
  GrabChopstick(this.philosopher);
}

/// message sent to a chopstick to release it
class ReleaseChopstick {
  final int philosopher;
  ReleaseChopstick(this.philosopher);
}

/**
 * An instance of Chopstick represents a chopstick on the dinner table.
 *
 * It responds to the messages [InitChopstick], [GrabChopstick] and
 * [ReleaseChopstick].
 */
class Chopstick {

  int _id;
  var _stateHandler;
  bool _taken = false;

  Chopstick() {
    _stateHandler = _whenInit;
    port.receive((message, replyTo) {
      _stateHandler(message,replyTo);
    });
  }

  _log(m) => print("chopstick $_id: $m");

  _whenInit(message, replyTo) {
    assert(message is InitChopstick);
    _id = message.id;
    _stateHandler = _whenActing;
  }

  _whenActing(message, replyTo) {
    if (message is GrabChopstick) {
      _handleGrabChopstick(message, replyTo);
    } else if (message is ReleaseChopstick) {
      _handleReleaseChopstick(message, replyTo);
    }
  }

  _handleGrabChopstick(message, replyTo) {
    if (!_taken) {
      _taken = true;
      _log("philosopher ${message.philosopher}: granted chopstick ...");
      replyTo.send(true);
    } else {
      _log("philosopher ${message.philosopher}: denied chopstick ...");
      replyTo.send(false);
    }
  }

  _handleReleaseChopstick(message, _) {
    assert(_taken);
    _log("philosopher ${message.philosopher}: released chopstick ...");
    _taken = false;
  }
}

chopstick() => new Chopstick();

/// message sent to a philosopher to initialize it
class InitPhilosopher {
  final int id;
  final SendPort left;
  final SendPort right;
  InitPhilosopher(this.id, this.left, this.right);
}

/// message sent to a philosopher to start the dinner
class StartDinner{}

/**
 * An instance of Philosopher represents a dining philosopher.
 *
 */
class Philosopher {
  int _id;
  var _stateHandler;
  SendPort _left;
  SendPort _right;

  Philosopher() {
    _stateHandler = _whenInit;
    port.receive((message, replyTo) {
      _stateHandler(message, replyTo);
    });
  }

  _log(m) => print("philosopher $_id: $m");

  _whenInit(message, _) {
    assert(message is InitPhilosopher);
    _id = message.id;
    _left = message.left;
    _right = message.right;
    _stateHandler = _whenActing;
  }

  _whenActing(message, replyTo) {
    if (message is StartDinner) {
      _thinkAndEat();
    }
  }

  Future _thinkAndEat() {
    _think()
    .then((_) => _acquireChopsticks())
    .then((_) => _eat())
    .then((_) => _releaseChopsticks())
    .then((_) => _thinkAndEat());
  }

  Future _acquireChopstick(chopstick)
    => chopstick.call(new GrabChopstick(_id));

  Future _releaseChopstick(chopstick) {
    chopstick.send(new ReleaseChopstick(_id));
    return new Future.value(null);
  }

  Future _releaseChopsticks() {
    _log("releasing chopsticks ...");
    return Future.wait([
      _releaseChopstick(_left),
      _releaseChopstick(_right)
    ]);
  }

  Future _acquireChopsticks() =>
    Future.wait([
      _acquireChopstick(_left),
      _acquireChopstick(_right)
    ])
    .then((List ret) {
      // successfully grabed the chopsticks ?
      if (ret.every((v) => v)) {
        _log("sucessfully grabed chopsticks ...");
        return new Future.value(null);
      }
      _log("failed to grab chopsticks ... retrying later");
      // release any chopstick and retry later
      if (ret[0]) _releaseChopstick(_left);
      if (ret[1]) _releaseChopstick(_right);
      return _sleep(1000)
      .then((_) => _acquireChopsticks());
    });

  Future _think(){
    _log("thinking ...");
    return _sleepRandom(2000);
  }

  Future _eat() {
    _log("eating ...");
    return _sleepRandom(2000);
  }
}

philosopher() => new Philosopher();

dine(n) {
  assert(n >= 2);
  new Table(n).dine();
}


