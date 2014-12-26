library dining_philosophers.dinner5;

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
 * Philosophers are initialized with the sendports of their
 * left and right fork. Before they start dining, they receive
 * the ids of this forks. A philosopher always picks up the
 * fork with the lower id first. He releases forks in opposite
 * order.
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
 * Represents a fork on the diner table.
 */
class Fork {

  static spawn(int id, SendPort replyTo) =>
      Isolate.spawn(_spawn, new InitForkReq(id, replyTo));
  static _spawn(InitForkReq init) => new Fork._(init);

  bool inUse = false;
  int id;
  SendPort pending = null;

  final ReceivePort _me = new ReceivePort();
  Stream _stream;

  Fork._(InitForkReq init) {
    id = init.id;
    _stream = _me.asBroadcastStream();
    init.replyTo.send(new InitForkAck(id, _me.sendPort));
    _stream.listen(_handleRequest);
  }

  _handlePickUp(PickUp msg) {
    if (inUse) {
      _log("pickup: already in use - remember request");
      pending = msg.replyTo;
    } else {
      _log("pickup: not in used yet - grant request");
      inUse = true;
      msg.replyTo.send(true);
    }
  }

  _handlePutDown(PutDown msg) {
    assert(inUse);
    if (pending != null) {
      _log("putDown: grant to pending request");
      pending.send(true);
      pending = null;
    } else {
      _log("putDown: free again");
      inUse = false;
    }
    msg.replyTo.send(null);
  }

  _handleQueryId(QueryId msg) {
    _log("query id ...");
    msg.replyTo.send(id);
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

  _log(m) => print("fork $id: $m");
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

class Philosopher {
  int _id;
  List _forks;

  static spawn(int id, List<SendPort> forks, SendPort replyTo)
    => Isolate.spawn(_spawn, new InitPhilosopher(id, forks, replyTo));
  static _spawn(InitPhilosopher init) => new Philosopher._(init);

  final ReceivePort _me = new ReceivePort();
  Stream _stream;

  Philosopher._(InitPhilosopher init) {
    _id = init.id;
    _forks = init.forks;
    _stream = _me.asBroadcastStream();
    init.replyTo.send(new InitPhilosopherAck(_id, _me.sendPort));

    Future awaitStartDinner() =>
      _stream.firstWhere((msg) => msg is StartDinner);

    Future startDinner(_) => _thinkAndEat();

    awaitStartDinner()
    .then(startDinner);
  }

  Future _thinkAndEat() {
    _log("think and eat ...");
    return _think()
    .then((_) => _pickUpForks())
    .then((_) => _eat())
    .then((_) => _putDownForks())
    .then((_) => _thinkAndEat());
  }

  Future _think() {
    _log("thinking ...");
    return sleepRandom(2000);
  }

  Future _eat() {
    _log("eating ...");
    return sleepRandom(2000);
  }

  Future _pickUpForks() {
    _log("pick up forks ...");
    final ReceivePort replyTo = new ReceivePort();
    _forks.forEach((fork) => fork.send(new PickUp(replyTo.sendPort)));
    return replyTo.take(2).toList().then((_) {
      replyTo.close();
      return new Future.value();
    });
  }

  Future _putDownForks() {
    _log("putting down forks ...");
    final ReceivePort replyTo = new ReceivePort();
    final msg = new PutDown(replyTo.sendPort);
    _forks.forEach((fork) => fork.send(msg));
    return replyTo.take(2).toList().then((_) {
        replyTo.close();
        return new Future.value();
    });
  }

  _log(m) => print("philosopher $_id: $m");
}


class Table {
  List<SendPort> _philosophers;
  List<SendPort> _forks = [];
  int _n;

  final Completer initialized = new Completer();

  Table(this._n) {
    _initForks()
    .then(_initPhilosophers)
    .then((_) => initialized.complete());
  }

  Future _initForks() {
    final ReceivePort replyTo = new ReceivePort();
    for (int i = 0; i < _n; i++) {
      Fork.spawn(i, replyTo.sendPort);
    }
    _forks = new List.filled(_n, null);
    return replyTo.take(_n).forEach((InitForkAck msg) {
      _forks[msg.id] = msg.port;
    });
  }

  Future _initPhilosophers(_) {
    final ReceivePort replyTo = new ReceivePort();
    for (int i = 0; i < _n; i++) {
      final forks = [this._forks[i], this._forks[(i + _n - 1) % _n]];
      Philosopher.spawn(i, forks, replyTo.sendPort);
    }
    _philosophers = new List.filled(_n, null);
    return replyTo.take(_n).forEach((InitPhilosopherAck msg) {
      _philosophers[msg.id] = msg.port;
    });
  }

  dine() {
    const msg = const StartDinner();
    start([_]) => _philosophers.forEach((p) => p.send(msg));
    initialized.future.then(start);
  }
}

dine(int n) {
  final table = new Table(n);
  table.dine();
  // to keep the program alive
  new ReceivePort()..listen((_){});
}

