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
import "dart:async";
import "sleep.dart";

class StartDinner {}

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

  List<SendPort> _chopsticks;
  var _philosophers;
  int _n;

  Completer setup = new Completer();

  Table(this._n) {
    assert(_n >= 2);
    _prepareTable()
    .then(_placePhilosophers)
    .then((_) => setup.complete());
  }

  Future _prepareTable() {
    ReceivePort port = new ReceivePort();
    for (var i=0; i<_n; i++) {
      Chopstick.spawn(i, port.sendPort);
    }
    _chopsticks = new List.filled(_n, null);
    return port.take(_n).forEach((SignUpChopstick msg) {
      _chopsticks[msg.id] = msg.chopstickPort;
    });
  }

  Future _placePhilosophers([_]) {
    ReceivePort port= new ReceivePort();
    for (int i=0; i< _n; i++) {
      var l = i;
      var r = (i + _n -1) % _n;
      Philosopher.spawn(i, _chopsticks[l], _chopsticks[r], port.sendPort);
    }
    _philosophers = new List.filled(_n, null);
    return port.take(_n).forEach((SignUpPhilosopher msg) {
      _philosophers[msg.id]= msg.port;
    });
  }

  dine() {
    start([_]) => _philosophers.forEach((p) => p.send(new StartDinner()));
    if (setup.isCompleted) {
      start();
    } else {
      setup.future.then(start);
    }
  }
}

class InitChopstick {
  final int id;
  final SendPort signUpAt;
  InitChopstick(this.id, this.signUpAt);
}

class SignUpChopstick {
  final int id;
  final SendPort chopstickPort;
  SignUpChopstick(this.id, this.chopstickPort);
}

/// message sent to a chopstick to grab it
class GrabChopstick {
  final int philosopher;
  final SendPort replyTo;
  GrabChopstick(this.philosopher, this.replyTo);
}

/// message sent to a chopstick to release it
class ReleaseChopstick {
  final int philosopher;
  ReleaseChopstick(this.philosopher);
}

/**
 * An instance of Chopstick represents a chopstick on the dinner table.
 *
 * It responds to the messages [GrabChopstick] and
 * [ReleaseChopstick].
 */
class Chopstick {

  /// spawns a chopstick isolate with [id]. The isolate signs up itself
  /// sending a [SignUpChopstick] message to [signUpAt]
  static spawn(int id, SendPort signUpAt) =>
      Isolate.spawn(_spawn,new InitChopstick(id, signUpAt));

  static _spawn(InitChopstick init) => new Chopstick._(init.id, init.signUpAt);

  int _id;
  bool _taken = false;
  ReceivePort _me = new ReceivePort();

  Chopstick._(this._id, SendPort signUpAt) {
    signUpAt.send(new SignUpChopstick(_id, _me.sendPort));
    _me.listen(_handleMessage);
  }

  _log(m) => print("chopstick $_id: $m");

  _handleMessage(message) {
    if (message is GrabChopstick) {
      _handleGrabChopstick(message);
    } else if (message is ReleaseChopstick) {
      _handleReleaseChopstick(message);
    }
  }

  _handleGrabChopstick(GrabChopstick message) {
    if (!_taken) {
      _taken = true;
      _log("philosopher ${message.philosopher}: granted chopstick ...");
      message.replyTo.send(true);
    } else {
      _log("philosopher ${message.philosopher}: denied chopstick ...");
      message.replyTo.send(false);
    }
  }

  _handleReleaseChopstick(ReleaseChopstick message) {
    assert(_taken);
    _log("philosopher ${message.philosopher}: released chopstick ...");
    _taken = false;
  }
}

/// message sent to a philosopher to initialize it
class InitPhilosopher {
  final int id;
  final SendPort leftChopstick;
  final SendPort rightChopstick;
  final SendPort signUpAt;
  InitPhilosopher(this.id, this.leftChopstick, this.rightChopstick, this.signUpAt);
}

class SignUpPhilosopher {
  final int id;
  final SendPort port;
  SignUpPhilosopher(this.id, this.port);
}

/**
 * An instance of Philosopher represents a dining philosopher.
 */
class Philosopher {

  /**
   * Spawn an isolate representing a dining philosoper with [id]. It uses the
   * two chopsticks [leftChopstick] and [rightChopsticks] and signs itself
   * up at the table by sending a [SignUpPhilosopher] message to
   * [signUpAt].
   */
  static spawn(int id, SendPort leftChopstick, SendPort rightChopstick, SendPort signUpAt) =>
      Isolate.spawn(_spawn, new InitPhilosopher(id, leftChopstick, rightChopstick, signUpAt));

  static _spawn(InitPhilosopher init) => new Philosopher._init(init);

  int _id;
  SendPort _left;
  SendPort _right;
  ReceivePort _me = new ReceivePort();

  Philosopher._init(InitPhilosopher init) {
    _id = init.id;
    _left = init.leftChopstick;
    _right = init.rightChopstick;
    init.signUpAt.send(new SignUpPhilosopher(_id, _me.sendPort));

    // when the dinner starts, start to eat
    _me.asBroadcastStream()
    .firstWhere((msg) => msg is StartDinner)
    .then(_thinkAndEat);
  }

  _log(m) => print("philosopher $_id: $m");

  Future _thinkAndEat([_]) =>
    _think()
    .then(_acquireChopsticks)
    .then(_eat)
    .then(_releaseChopsticks)
    .then(_thinkAndEat);


  Future _acquireChopstick(SendPort chopstick) {
    ReceivePort port = new ReceivePort();
    chopstick.send(new GrabChopstick(_id, port.sendPort));
    return port.first;
  }

  Future _releaseChopstick(SendPort chopstick) {
    chopstick.send(new ReleaseChopstick(_id));
    return new Future.value();
  }

  Future _releaseChopsticks([_]) {
    _log("releasing chopsticks ...");
    return Future.wait([
      _releaseChopstick(_left),
      _releaseChopstick(_right)
    ]);
  }

  Future _acquireChopsticks([_]) =>
    Future.wait([
      _acquireChopstick(_left),
      _acquireChopstick(_right)
    ])
    .then((List ret) {
      var success = ret.every((ok) => ok);
      // successfully grabed the chopsticks ?
      if (success) {
        _log("sucessfully grabed chopsticks ...");
        return new Future.value();
      }
      _log("failed to grab chopsticks ... retrying later");
      // release any chopstick and retry later
      if (ret[0]) _releaseChopstick(_left);
      if (ret[1]) _releaseChopstick(_right);
      return sleepRandom(1000)
      .then(_acquireChopsticks);
    });

  Future _think([_]){
    _log("thinking ...");
    return sleepRandom(2000);
  }

  Future _eat([_]) {
    _log("eating ...");
    return sleepRandom(2000);
  }
}

/// Run a dinner with [n] philosophers (n >= 2).
dine(int n) {
  assert(n >= 2);
  new Table(n)..dine();
  // to keep the program alive
  new ReceivePort()..listen((_){});
}


