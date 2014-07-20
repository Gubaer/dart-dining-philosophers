library dining_philosophers.dinner1;
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
 * Philosophers use a polling aproach to acquire chopsticks. If they fail
 * to acquire both required chopsticks, they retry after a short delay.
 *
 */

import "dart:isolate";
import "dart:async";
import "sleep.dart";

/**
 * Send by the philosopher [id] to acquire both chopsticks. Expects
 * a boolean on the port [replyTo].
 */
class AcquireChopsticks {
  final int id;
  final SendPort replyTo;
  const AcquireChopsticks(this.id, this.replyTo);
}

/**
 * Send by the philosopher [id] to release both chopsticks.
 */
class ReleaseChopsticks {
  final int id;
  const ReleaseChopsticks(this.id);
}

/**
 * The table where the philosophers are sitting.
 *
 * A running table isolate manages the chopsticks the philosophers use.
 * Aquiring or releasing both chopsticks is an atomic action. A philosopher
 * sends a request to use both chopsticks to the table. Use is either granted
 * or denied by the table.
 */
class Table {

  /// spawns an isolate for a table with [n] philosophers
  static Future<Isolate> spawn(int n) => Isolate.spawn(_spawn, n);

  static _spawn(int n) => new Table._(n);

  int _n;
  List<bool> _taken;
  ReceivePort _port = new ReceivePort();

  Table._(this._n) {
    _taken = new List.filled(_n, false);
    _placePhilosophers();
    _port.listen(_handleMessage);
  }

  _placePhilosophers() {
    for (var i = 0; i < _n; i++) {
      Philosopher.spawn(i, _port.sendPort);
    }
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
    }
  }
}

/**
 * Message to initialize a philosopher [i] sitting at a [table]
 */
class InitPhilosopher {
  /// the philosopher id
  final int i;
  /// the port of the table isolate
  final SendPort table;
  const InitPhilosopher(this.i, this.table);
}

/**
 * An instance of Philosopher represents a thinking and eating philosopher.
 */
class Philosopher {
  int _i;
  SendPort _table;
  ReceivePort _port;

  /// spawns an isolate for a philosopher [i] sitting at [table]
  static Future<Isolate> spawn(int i, SendPort table) =>
      Isolate.spawn(_spawn, new InitPhilosopher(i, table));

  static _spawn(InitPhilosopher init) => new Philosopher._(init.i, init.table);

  Philosopher._(this._i, this._table) {
    _port = new ReceivePort();
    _thinkAndEat();
  }

  _log(message) => print("philosopher $_i: $message");

  _thinkAndEat([_]) {
    _think()
    .then((_) {
      _log("acquire chopsticks ... START");
      _aquireChopsticks(_);
    })
    .then(_eat)
    .then(_releaseChopsticks)
    .then(_thinkAndEat);
  }

  Future _aquireChopsticks([_]) {
    ReceivePort result = new ReceivePort();
    _table.send(new AcquireChopsticks(_i, result.sendPort));
    return result.first.then((success) {
      result.close();
      if (success) {
        _log("acquire chopsticks ... DONE");
        return new Future.value();
      }
      // aquiring chopsticks failed, try again later
      return sleep(1000)
      .then(_aquireChopsticks);
    });
  }

  Future _releaseChopsticks(_) {
    _log("releasing chopsticks ...");
    _table.send(new ReleaseChopsticks(_i));
    return new Future.value();
  }

  Future _think([_]) {
    _log("thinking ...");
    return sleepRandom(2000);
  }

  Future _eat([_]) {
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
