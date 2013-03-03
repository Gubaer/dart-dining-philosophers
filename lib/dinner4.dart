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
import "dart:async";
import "dart:math";

var _random = new Random();

/// completes after [delay] ms with value null
Future _sleep(delay) => new Future.delayed(
    new Duration(milliseconds: delay), ()=>null);

/// completes after a random number of `ms` in the range
/// 0..[range] with value null
Future _sleepRandom(range) => _sleep(_random.nextInt(range));

/// a fork
class Fork {
  /// the fork id
  final int id;
  Fork(this.id);
  bool dirty = true;  // initially forks are dirty
}

/// represents a request for a fork
class ForkRequest {
  final int id;
  ForkRequest(this.id);
}

/// three states of philosopher
const THINKING  = 0;
const HUNGRY = 1;
const EATING = 2;

/**
 * message to initialize a philosopher
 */
class InitPhilosopher {
  final SendPort left;
  final SendPort right;
  final int id;
  final int numPhilosophers;
  InitPhilosopher(this.id, this.numPhilosophers, this.left, this.right);
}

/// message to start the dinner
class StartDinner {}

/**
 * An instance of this class represents a philosopher
 */
class Philosopher {
  static const int LEFT = 0;
  static const int RIGHT = 1;

  /// philosopher id
  int _id;
  int _numPhilosophers;

  /// send ports of the neighbouring philosophers
  List<SendPort> _neighbours = new List.fixedLength(2, fill: null);

  /// the left and right forks.
  List<Fork> _forks = new List.fixedLength(2, fill:null);

  /// the left and right forksrequests
  List<ForkRequest> _forkRequests = new List.fixedLength(2, fill: null);

  /// the ids of the left and right fork
  List<int> _forkIds = new List.fixedLength(2, fill: null);

  /// the ids of the left and right philosopher
  List<int> _philoIds = new List.fixedLength(2, fill: null);

  int _state;

  Philosopher() {
    port.receive(_handleWhenInit);
  }

  _log(m) => print("philosopher $_id: $m");

  _init(InitPhilosopher message) {
    _id = message.id;
    _numPhilosophers = message.numPhilosophers;
    _forkIds = [(_id + _numPhilosophers -1) % _numPhilosophers, _id];
    _neighbours = [message.left, message.right];
    _philoIds = [(_id + _numPhilosophers - 1) % _numPhilosophers, (_id + 1) % _numPhilosophers];
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
      _forks[LEFT]  = new Fork(_forkIds[LEFT]);
    } else {
      _forkRequests[LEFT] = new ForkRequest(_forkIds[LEFT]);
      _forks[RIGHT]  = new Fork(_forkIds[RIGHT]);
    }
    _log("initialized ... forks:[$_forksAsString], requests:[$_forkRequestsAsString]");
  }

  /// handles messages [InitPhilosopher] and [StartDinner]
  /// when the this philosopher is initializing
  _handleWhenInit(message, _) {
    if (message is InitPhilosopher) {
      _init(message);
    } else if (message is StartDinner) {
      _log("starting dinner ...");
      port.receive(_handleWhenActing);
      _think();
    }
  }

  /// handles messages when the philosopher is acting, i.e. when he is thinking, hungry,
  /// or eating
  _handleWhenActing(message, replyTo) {
    if (message is Fork) {
      var fork = (message as Fork);
      assert(!fork.dirty);                // only clean forks
      assert(_forkIds.contains(fork.id)); // only neighbouring forks
      assert(_forks.where((f) => f != null && f.id == fork.id).isEmpty); // don't have the fork yet
      if (fork.id == _forkIds[RIGHT]) {
        _log("received right fork ${fork.id}");
        assert(!_fork(RIGHT)); // should have the fork yet
        _forks[RIGHT] = fork;
      } else {
        _log("received left fork ${fork.id}");
        assert(!_fork(LEFT));  // should have the fork yet
        _forks[LEFT] = fork;
      }
      _evaluateState();
    } else if (message is ForkRequest) {
      var request = (message as ForkRequest);
      assert(_forkIds.contains(request.id)); // only request for neighbouring forks
      if (request.id == _forkIds[RIGHT]) {
        _log("received right fork request for fork ${message.id}");
        assert(!_reqf(RIGHT));  // shouldn't already have a fork request
        _forkRequests[RIGHT] = message;
      } else {
        _log("received left fork request for fork ${message.id}");
        assert(!_reqf(LEFT)); // shouldn't already have a fork request
        _forkRequests[LEFT] = message;
      }
      _evaluateState();
    }
  }

  get _forkRequestsAsString => _forkRequests.map((r) => r == null ? "null" : "<${r.id}>").join(",");
  get _forksAsString => _forks.map((f) => f == null ? "null" : "<${f.id}/${f.dirty}>").join(",");

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
      _log("sending fork request ${_forkRequests[side].id} to ${_neighbourId(side)}");
      _neighbours[side].send(_forkRequests[side]);
      _forkRequests[side] = null;
    }
  }

  _evaluateStateHungry() {
    _log("evaluate 'hungry' ... forks:[$_forksAsString,] request: [$_forkRequestsAsString]");
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
    _log("evaluate 'thinking' ... forks:[$_forksAsString], request: [$_forkRequestsAsString]");
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
    switch(_state) {
      case HUNGRY: _evaluateStateHungry(); break;
      case THINKING: _evaluateStateThinking(); break;
      case EATING: /* while eating the philosopher doesn't respond */ break;
    }
  }

  _think() {
    _state = THINKING;
    _log("thinking ... START");
    _sleepRandom(2000)
    .then((_) {
      _log("thinking ... END");
      _state = HUNGRY;
      _evaluateState();
    });
  }

  _eat() {
    _state = EATING;
    _log("eating ... START");
    _forks.forEach((f) => f.dirty = true);
    _sleepRandom(2000).then((_) {
      _log("eating ... END");
      _state = THINKING;
      _evaluateState();
      _think();
    });
  }
}

philosopher() => new Philosopher();

class Table {
  final int n;
  Table(this.n);

  var _philosophers = [];

  dine() {
    for (int i=0; i<n; i++) {
      _philosophers.add(spawnFunction(philosopher));
    }

    for(int i=0; i< n; i++) {
      var p = _philosophers[i];
      var left = _philosophers[(i + n -1) % n];
      var right = _philosophers[(i+1) % n];
      p.send(new InitPhilosopher(i, n, left, right));
    }

    var msg = new StartDinner();
    _philosophers.forEach((p) => p.send(msg));
  }
}

dine(n) {
  new Table(n).dine();
}

