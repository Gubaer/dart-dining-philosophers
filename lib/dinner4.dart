library dining_philosophers.dinner4;
/**
 * This is an implementation of the dining philosopher problem based
 * on terminology and algorithm from the paper
 *
 * Chandy, K.M; Misra; J.
 * The Drinking Philosophers Problem
 *
 * http://www.cs.utexas.edu/users/misra/scannedPdf.dir/DrinkingPhil.pdf
 */
import "dart:isolate";
import "sleep.dart";
import "dart:async";

class Fork {
  final int id;
  Fork(this.id);
  bool dirty = true; // initially forks are dirty
}

class ForkRequest {
  final int id;
  ForkRequest(this.id);
}

/// three states of a philosopher
const THINKING = 0;
const HUNGRY = 1;
const EATING = 2;

class InitPhilosopher {
  final SendPort table;
  final int id;
  final int numPhilosophers;
  InitPhilosopher(this.table, this.id, this.numPhilosophers);
}

class InitNeighbours {
  final SendPort left;
  final SendPort right;
  final SendPort replyTo;
  InitNeighbours(this.left, this.right, this.replyTo);
}

/// emitted by a philosopher to register itself at the table
class RegisterPhilosopher {
  final int id;
  final SendPort port;
  RegisterPhilosopher(this.id, this.port);
}

/// message to start the dinner
class StartDinner {
  const StartDinner();
}

/// an instance of this class represents a dining philosopher
class Philosopher {

  /**
   * Spawn a philosopher [id] sitting with [numPhilosophers] at a [table].
   *
   * Registers itself at [table] sending a [RegisterPhilosopher] message to it.
   */
  static spawn(SendPort table, int id, int numPhilosophers) =>
      Isolate.spawn(_spawn, new InitPhilosopher(table, id, numPhilosophers));

  static _spawn(InitPhilosopher init) => new Philosopher._init(init);

  static const int LEFT = 0;
  static const int RIGHT = 1;

  /// philosopher id
  int _id;
  /// num philosophers
  int _n;

  /// send ports of the neighbouring philosophers
  List<SendPort> _neighbours;

  /// the left and right forks.
  final List<Fork> _forks = new List.filled(2, null);

  /// the left and right forksrequests
  final List<ForkRequest> _forkRequests = new List.filled(2, null);

  /// the ids of the left and right fork
  List<int> _forkIds;

  /// the ids of the left and right philosopher
  List<int> _philoIds;

  int _state;

  final ReceivePort _me = new ReceivePort();

  Philosopher._init(InitPhilosopher init) {
    _id = init.id;
    _n = init.numPhilosophers;
    _forkIds = [(_id + _n - 1) % _n, _id];
    _philoIds = [(_id + _n - 1) % _n, (_id + 1) % _n];

    _log("initialized ... forks:[$_forksAsString], requests:[$_forkRequestsAsString]");

    init.table.send(new RegisterPhilosopher(_id, _me.sendPort));

    final stream = _me.asBroadcastStream();

    Future handleInitNeighbours() {
        return stream.firstWhere((msg) => msg is InitNeighbours)
        .then((InitNeighbours msg) {
          _neighbours = [msg.left, msg.right];
          /*
          * Initially, the depedency graph has to be acyclic according to
          * Chandy/Misra. For philosopher 0, left and right are therefore
          * reversed.
          * Furthermore, all philosophers are initialized with the left fork, expect
          * philosopher 0, which is initialized with the right fork and
          * the fork request for the left fork.
          */
          if (_id == 0) {
            _forkIds = _forkIds.reversed.toList();
            _neighbours = _neighbours.reversed.toList();
            _philoIds = _philoIds.reversed.toList();
          }
          if (_id == 0) {
            _forkRequests[RIGHT] = new ForkRequest(_forkIds[RIGHT]);
            _forks[LEFT] = new Fork(_forkIds[LEFT]);
          } else {
            _forkRequests[LEFT] = new ForkRequest(_forkIds[LEFT]);
            _forks[RIGHT] = new Fork(_forkIds[RIGHT]);
          }
          msg.replyTo.send(true);
        });
     }

     Future handleStartDinner(_) {
        return stream.firstWhere((msg) => msg is StartDinner);
     }

     startEating(_) {
       stream.listen(_handleMessage);
       _think();
     }

     handleInitNeighbours()
     .then(handleStartDinner)
     .then(startEating);
  }

  _log(m) => print("philosopher $_id: $m");

  _handleFork(Fork fork) {
     assert(!fork.dirty); // only clean forks
     assert(_forkIds.contains(fork.id)); // only neighbouring forks
     assert(_forks.where(
         (f) => f != null && f.id == fork.id).isEmpty); // don't have the fork yet
     if (fork.id == _forkIds[RIGHT]) {
       _log("received right fork ${fork.id}");
       assert(!_fork(RIGHT)); // shouldn't have the fork yet
       _forks[RIGHT] = fork;
     } else {
       _log("received left fork ${fork.id}");
       assert(!_fork(LEFT)); // shouldn't have the fork yet
       _forks[LEFT] = fork;
     }
     _evaluateState();
   }

  _handleForkRequest(ForkRequest request) {
    assert(_forkIds.contains(request.id)); // only request for neighbouring forks
    if (request.id == _forkIds[RIGHT]) {
      _log("received right fork request for fork ${request.id}");
      assert(!_reqf(RIGHT)); // shouldn't already have a fork request
      _forkRequests[RIGHT] = request;
    } else {
      _log("received left fork request for fork ${request.id}");
      assert(!_reqf(LEFT)); // shouldn't already have a fork request
      _forkRequests[LEFT] = request;
    }
    _evaluateState();
  }

  _handleMessage(message) {
    if (message is Fork) {
      _handleFork(message);
    } else if (message is ForkRequest) {
      _handleForkRequest(message);
    } else {
      assert(false); // unexpected message
    }
  }

  get _forkRequestsAsString =>
      _forkRequests.map((r) => r == null ? "null" : "<${r.id}>").join(",");
  get _forksAsString =>
      _forks.map((f) => f == null ? "null" : "<${f.id}/${f.dirty}>").join(",");

  _neighbourId(side) => _philoIds[side];

  /// send the fork of [side] (either [LEFT] or [RIGHT]) to the
  /// neighbouring philosopher, if possible
  _sendForkIfPossible(side) {
    if (_fork(side) && _dirty(side) && _reqf(side)) {
      _forks[side].dirty = false;
      _log("sending fork ${_forks[side].id} to ${_neighbourId(side)}");
      _neighbours[side].send(_forks[side]);
      _forks[side] = null;
    }
  }

  /// send the fork request for the fork of [side] (either [LEFT] or [RIGHT]) to the
  /// neighbouring philosopher, if possible
  _sendForkRequestIfPossible(side) {
    if (!_fork(side) && _reqf(side)) {
      _log(
          "sending fork request ${_forkRequests[side].id} to ${_neighbourId(side)}");
      _neighbours[side].send(_forkRequests[side]);
      _forkRequests[side] = null;
    }
  }

  _evaluateStateHungry() {
    _log(
        "evaluate 'hungry' ... forks:[$_forksAsString,] request: [$_forkRequestsAsString]");
    // both forks available -> start eating
    if (_fork(LEFT) && _fork(RIGHT)) {
      _eat();
    } else {
      // missing a fork?
      // request it as soon as the request token is present
      _sendForkRequestIfPossible(LEFT);
      _sendForkRequestIfPossible(RIGHT);

      // do we have a  dirty  fork and got a fork request?
      // clear and send the fork
      _sendForkIfPossible(LEFT);
      _sendForkIfPossible(RIGHT);
    }
  }

  _evaluateStateThinking() {
    _log(
        "evaluate 'thinking' ... forks:[$_forksAsString], request: [$_forkRequestsAsString]");
    // do we have a  dirty  fork and got a fork request?
    // clear and send the fork
    _sendForkIfPossible(LEFT);
    _sendForkIfPossible(RIGHT);
  }

  // predicates used in the paper from Chandy/Misra
  bool _reqf(side) => _forkRequests[side] != null;
  bool _fork(side) => _forks[side] != null;
  bool _dirty(side) => _forks[side].dirty;

  _evaluateState() {
    switch (_state) {
      case HUNGRY:
        _evaluateStateHungry();
        break;
      case THINKING:
        _evaluateStateThinking();
        break;
      case EATING:
        /* while eating the philosopher doesn't respond */ break;
    }
  }

  _think() {
    _state = THINKING;
    _log("thinking ... START");
    sleepRandom(2000).then((_) {
      _log("thinking ... END");
      _state = HUNGRY;
      _evaluateState();
    });
  }

  _eat() {
    _state = EATING;
    _log("eating ... START");
    _forks.forEach((f) => f.dirty = true);
    sleepRandom(2000).then((_) {
      _log("eating ... END");
      _state = THINKING;
      _evaluateState();
      _think();
    });
  }
}

class Table {
  final int n;
  List<SendPort> _philosophers;

  Table(this.n) {
    _philosophers = new List.filled(n, null);
  }

  dine() {
    final me = new ReceivePort();
    final stream = me.asBroadcastStream();

    Future spawnPhilosophers() {
      for (var i = 0; i < n; i++) {
         Philosopher.spawn(me.sendPort, i, n);
      }
      return stream.take(n).forEach((RegisterPhilosopher msg){
         _philosophers[msg.id] = msg.port;
      });
    }

    Future initNeighbours(_) {
      for (var i = 0; i < n; i++) {
        final left = _philosophers[(i + n - 1) % n];
        final right = _philosophers[(i + 1) % n];
        _philosophers[i].send(new InitNeighbours(left, right, me.sendPort));
      }
      return stream.take(n).toList();
    }

    startDinner(_) {
      _philosophers.forEach((p) => p.send(const StartDinner()));
    }

    spawnPhilosophers()
      .then(initNeighbours)
      .then(startDinner);
  }
}

dine(n) {
  new Table(n)..dine();
  // to keep the program alive
  new ReceivePort()..listen((_){});
}
