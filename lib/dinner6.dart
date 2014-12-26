library dining_philosophers.dinner6;

/**
 * This is a solution for the dining philosopher problem based on
 * Dijkstras aproach.
 *
 * See *Resource hierarchy solution* in
 * http://en.wikipedia.org/wiki/Dining_philosophers_problem
 *
 * The solution consists of:
 *   * n actors for n dining philosophers
 *   * n actors for n forks
 *
 * Forks have a unique numeric id. They are partially orded
 * by this id.
 *
 * Philosophers are initialized with the send ports of their
 * left and right fork. Before they start dining, they receive
 * the ids of this forks. A philosopher always picks up the
 * fork with the lower id first. He releases forks in opposite
 * order.
 *
 * This version uses the new async/await language features.
 */

import "dart:isolate";
import "dart:async";
import 'sleep.dart';

class InitTable {
  /// the number of philosophers. n>=2 expected.
  final int n;
  InitTable(this.n) {
    assert(n >= 2);
  }
}

/// message to initialize a fork
class InitForkReq {
  final int id;
  final SendPort replyTo;
  InitForkReq(this.id, this.replyTo);
}

class InitForkAck {
  final int id;
  final SendPort port;
  InitForkAck(this.id, this.port);
}

class PickUp {
  final SendPort replyTo;
  PickUp(this.replyTo);
}
class PutDown {
  final SendPort replyTo;
  PutDown(this.replyTo);
}

class QueryId {
  final SendPort replyTo;
  QueryId(this.replyTo);
}

/**
 * Represents a fork on the dinner table.
 */
class Fork {

  /// spwan a fork isolate with an [id]. It sends a [InitForkAck]
  /// to [replyTo] when the isolate is initialized.
  static spawn(int id, SendPort replyTo) =>
      Isolate.spawn(_spawn, new InitForkReq(id, replyTo));

  static _spawn(InitForkReq init) => new Fork._(init);

  bool _inUse = false;
  final int _id;
  SendPort _pending = null;

  final ReceivePort _me = new ReceivePort();

  Fork._(InitForkReq init)
      : _id = init.id {
    init.replyTo.send(new InitForkAck(_id, _me.sendPort));
    _me.asBroadcastStream().listen(_handleRequest);
  }

  _handlePickUp(PickUp msg) {
    if (_inUse) {
      _log("pickup: already in use - remember request");
      _pending = msg.replyTo;
    } else {
      _log("pickup: not in used yet - grant request");
      _inUse = true;
      msg.replyTo.send(true);
    }
  }

  _handlePutDown(PutDown msg) {
    assert(_inUse);
    if (_pending != null) {
      _log("putDown: grant to pending request");
      _pending.send(true);
      _pending = null;
    } else {
      _log("putDown: free again");
      _inUse = false;
    }
    msg.replyTo.send(null);
  }

  _handleQueryId(QueryId msg) {
    _log("query id ...");
    msg.replyTo.send(_id);
  }

  /// handles messages after the initialization phase
  _handleRequest(message) {
    if (message is PickUp) {
      _handlePickUp(message);
    } else if (message is PutDown) {
      _handlePutDown(message);
    } else if (message is QueryId) {
      _handleQueryId(message);
    }
  }

  _log(m) => print("fork $_id: $m");
}

/// message sent to initialize a philosopher
class InitPhilosopher {
  final int id;
  final List<SendPort> forks;
  final SendPort replyTo;
  InitPhilosopher(this.id, this.forks, this.replyTo);
}

class InitPhilosopherAck {
  final int id;
  final SendPort port;
  InitPhilosopherAck(this.id, this.port);
}

/// message sent to start the dinner
class StartDinner {
  const StartDinner();
}

/// Represents a philosopher sitting at the table
class Philosopher {

  /// Spawns an isolate representing a philosopher with [id] using
  /// two [forks].
  /// After initialization it sends a [InitPhilosopherAck] to
  /// [replyTo].
  static spawn(int id, List<SendPort> forks, SendPort replyTo)
    => Isolate.spawn(_spawn, new InitPhilosopher(id, forks, replyTo));

  static _spawn(InitPhilosopher init) => new Philosopher._(init);

  final ReceivePort _me = new ReceivePort();
  final int _id;
  final List _forks;

  Philosopher._(InitPhilosopher init)
    : _id = init.id, _forks = init.forks {
    init.replyTo.send(new InitPhilosopherAck(_id, _me.sendPort));

    _me.firstWhere((msg) => msg is StartDinner)
       .then((_) => _thinkAndEat());
  }

  _thinkAndEat() async {
    _log("thinkAndEat ...");
    await _think();
    await _pickUpForks();
    await _eat();
    await _putDownForks();
    await _thinkAndEat();
  }

  _think() async {
    _log("thinking ...");
    await sleepRandom(2000);
  }

  _eat() async {
    _log("eating ...");
    await sleepRandom(2000);
  }

  _pickUpForks() async {
    final replyTo = new ReceivePort();
    _forks.forEach((fork) => fork.send(new PickUp(replyTo.sendPort)));
    await replyTo.take(2);
    await replyTo.close();
  }

  _putDownForks() async {
    _log("putting down forks ...");
    final replyTo = new ReceivePort();
    final msg = new PutDown(replyTo.sendPort);
    _forks.forEach((fork) => fork.send(msg));
    await replyTo.take(2);
    await replyTo.close();
  }

  _log(m) => print("philosopher $_id: $m");
}

class Table {
  List<SendPort> _philosophers;
  List<SendPort> _forks = [];
  final int _n;

  final Completer _initialized = new Completer();

  Table(this._n) {
    _initForks()
    .then((_) => _initPhilosophers())
    .then((_) => _initialized.complete());
  }

 _initForks() async {
    final replyTo = new ReceivePort();
    for (var i = 0; i < _n; i++) {
      Fork.spawn(i, replyTo.sendPort);
    }
    _forks = new List.filled(_n, null);
    await replyTo.take(_n)
          .forEach((msg) => _forks[msg.id] = msg.port);
  }

  _initPhilosophers() async {
    final replyTo = new ReceivePort();
    for (var i = 0; i < _n; i++) {
      final forks = [this._forks[i], this._forks[(i + _n - 1) % _n]];
      Philosopher.spawn(i, forks, replyTo.sendPort);
    }
    _philosophers = new List.filled(_n, null);
    await replyTo.take(_n)
          .forEach((msg) => _philosophers[msg.id] = msg.port);
  }

  dine() async {
    await _initialized.future;
    _philosophers.forEach((p) => p.send(const StartDinner()));
  }
}

dine(int n) {
  assert(n >= 2);
  final table = new Table(n);
  table.dine();
  // to keep the program alive
  new ReceivePort()..listen((_){});
}

