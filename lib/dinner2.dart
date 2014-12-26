library dining_philosophers.dinner2;
/**
 * This version of a dinner of philosophers consists of the following
 * actors:
 *
 * 1 an actor running a [Table]
 * 2 _n_ actors running individual [Philosopher]s
 *
 * Chopsticks aren't represented as actors. The [Table] isolate is responsible
 * for controlling access to chopsticks. It responds to the messages
 * [AcquireChopstick] and [ReleaseChopstick] and atomically grants or rejects
 * access to both the necessary chopsticks for a philosopher.
 *
 * Philosophers don't use polling  to acquire chopsticks. When new
 * chopsticks become available, the the table notifies all philosophers. Hungry
 * philosopher which already failed to acquire chopsticks retry to acquire
 * them after they got a notification from the table.
 *
 */

import "dart:isolate";
import "dart:async";
import "sleep.dart";

/// initializes the table with the number of philosophers
class InitTable {
  /// the number of philosophers. n>=2 expected.
  final int n;
  InitTable(this.n) {
    assert(n >= 2);
  }
}

class AcquireChopsticks {
  final int id;
  final SendPort replyTo;
  const AcquireChopsticks(this.id, this.replyTo);
}

class ReleaseChopsticks {
  final int id;
  const ReleaseChopsticks(this.id);
}

class NotifyChopsticksAvailable{}


/// Message to initialize a philosopher
class InitPhilosopher {
  /// the philosopher id
  final int i;
  /// the port of the table isolate
  final SendPort table;
  /// where to send an acknowledgement to
  final SendPort replyTo;
  InitPhilosopher(this.i, this.table, this.replyTo);
}

/// Message to acknowledge the initialization of a philosopher
class InitPhilosopherAck {
  final int id;
  final SendPort port;
  const InitPhilosopherAck(this.id, this.port);
}

/**
 * The table where the philosophers are sitting.
 *
 * A running table isolate manages the chopsticks the philosophers use.
 * Aquiring or rerelising both chopsticks is an atomic action. A philosophers
 * sends a request to use both chopsticks to the table. Use is either granted
 * or denied by the table.
 */
class Table {

  /// spawns an isolate for a table with [n] philosophers
  static Future<Isolate> spawn(int n) => Isolate.spawn(_spawn, n);
  static _spawn(int n) => new Table(n);

  int _n;
  List<bool> _taken = <bool>[];
  List<SendPort> _philosophers = [];
  ReceivePort _me = new ReceivePort();

  Table(this._n) {
    _taken = new List.filled(_n, false);
    _philosophers = new List.filled(_n, null);
    _me.listen(_handleMessage);
    _placePhilosophers();
  }

  Future _placePhilosophers() {
    final replyTo = new ReceivePort();
     for (var i = 0; i < _n; i++) {
       Philosopher.spawn(i, _me.sendPort, replyTo.sendPort);
     }
     return replyTo.take(_n)
         .forEach((msg) => _philosophers[msg.id] = msg.port);
   }

  _log(message) => print("table: $message");

  _isTaken(i) => _taken[i] || _taken[(i + _n -1) % _n];
  _setTaken(i, bool state) {
    _taken[i] = state;
    _taken[(i + _n -1) % _n] = state;
  }

  /// pick up the chopsticks for philosopher [i]
  _pickUp(i) => _setTaken(i, true);

  /// put down the chopsticks for philosopher [i]
  _putDown(i) => _setTaken(i, false);

  _handleMessage(message) {
    _log("handling $message ...");
    if (message is AcquireChopsticks) {
      if (! _isTaken(message.id)) {
        _pickUp(message.id);
        _log("philo ${message.id}: granted both chopsticks ...");
        message.replyTo.send(true);
      } else {
        message.replyTo.send(false);
      }
    } else if (message is ReleaseChopsticks) {
      _putDown(message.id);
      _log("philo ${message.id}: released chopsticks ...");
      _notifyChopstickAvailable();
    } else {
      assert(false);
    }
  }

  /// notifies all philosophers that chopsticks are available
  _notifyChopstickAvailable() =>
    _philosophers.forEach((p) => p.send(new NotifyChopsticksAvailable()));

}

/// An instance of Philosopher represents a thinking and eating philosopher.
class Philosopher {

  /// spawn an isolate representing a philosopher [i] sitting at a
  /// [table].
  /// After initialization the philosopher sends a [InitPhilosopherAck]
  /// to [replyTo].
  static Future<Isolate> spawn(int i, SendPort table, SendPort replyTo) =>
      Isolate.spawn(_spawn, new InitPhilosopher(i, table, replyTo));

  static _spawn(InitPhilosopher init) =>
      new Philosopher._(init.i, init.table, init.replyTo);

  final int _i;
  final SendPort _table;
  final ReceivePort _me = new ReceivePort();
  final SendPort _replyTo;
  bool _waitingForAvailableChopsticks = false;

  Philosopher._(this._i, this._table, this._replyTo) {
    _replyTo.send(new InitPhilosopherAck(_i, _me.sendPort));

    _me.where((msg) => msg is NotifyChopsticksAvailable)
       .listen((_) => _handleAcquireChopstickNotification());

    _thinkThenEat();
  }

  _log(message) => print("philosopher $_i: $message");

  _thinkThenEat() {
    _think()
    .then((_) => _acquireChopsticksThenEat());
  }

   _handleAcquireChopstickNotification() {
    if (_waitingForAvailableChopsticks) {
      _log("got notified to acquire chopsticks...");
      _waitingForAvailableChopsticks = false;
      _acquireChopsticksThenEat();
    }
  }

  Future _acquireChopsticksThenEat() {
    return _aquireChopsticks()
    .then((success) {
      if (!success) {
        _waitingForAvailableChopsticks = true;
        return new Future.value();
      }
      return _eat()
      .then((_) => _releaseChopsticks())
      .then((_) => _thinkThenEat());
    });
  }

  Future _aquireChopsticks() {
    ReceivePort result = new ReceivePort();
    _table.send(new AcquireChopsticks(_i, result.sendPort));
    return result.first.then((success) {
      result.close();
      return success;
    });
  }

  Future _releaseChopsticks() {
    _log("releasing chopsticks ...");
    _table.send(new ReleaseChopsticks(_i));
    return new Future.value(null);
  }

  Future _think(){
    _log("thinking ...");
    return sleepRandom(2000);
  }

  Future _eat() {
    _log("eating  ...");
    return sleepRandom(2000);
  }
}

dine(n) {
  assert(n >= 2);

  Table.spawn(n);
  // to keep the program alive
  new ReceivePort()..listen((_){});
}