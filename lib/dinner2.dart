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
 * Philosophers don't use polling  to acquire chopsticks. When new
 * chopsticks become available, the the table notifies all philosophers. Hungry
 * philosopher which already failed to acquire chopsticks retry to acquire
 * them after they got a notification from the table. 
 * 
 */

import "dart:isolate";
import "dart:math";
import "dart:async";

var _random = new Random();

/// completes after [delay] ms with value null
Future _sleep(delay) => new Future.delayed(delay, ()=>null);
/// completes after a random number of `ms` in the range
/// 0..[range] with value null
Future _sleepRandom(range) => _sleep(_random.nextInt(range));

/// initializes the table with the number of philosophers 
class InitTable {
  /// the number of philosophers. n>=2 expected.
  final int n;
  InitTable(this.n) {
    assert(n >= 2);
  }
}

/**
 * Messages to acquire both chopsticks.
 * 
 * Sent by a philosopher to the table. 
 */
class AcquireChopsticks {
  /// the philosopher id 
  final int philosopher;
  const AcquireChopsticks(this.philosopher);
}

/**
 * Messages to release both chopsticks.
 * 
 * Sent by a philosopher to the table. 
 */
class ReleaseChopsticks {
  /// the philosopher id 
  final int philosopher;
  const ReleaseChopsticks(this.philosopher);
}

class NotifyChopsticksAvailable{}

/**
 * The table where the philosophers are sitting.
 * 
 * A running table isolate manages the chopsticks the philosophers use.
 * Aquiring or rerelising both chopsticks is an atomic action. A philosophers
 * sends a request to use both chopsticks to the table. Use is either granted
 * or denied by the table.  
 */
class Table {
  static const STATE_INIT = 0;
  static const STATE_ACTING = 1;
  
  var _n;
  var _state = STATE_INIT;
  var _taken = <bool>[];
  var _philosophers = [];
  
  Table() {
    port.receive((message, replyTo) {
      switch(_state) {
        case STATE_INIT: _whenInit(message, replyTo); break;
        case STATE_ACTING: _whenActing(message, replyTo); break;
      }
    });    
  }
  
  get _takenToString  => Strings.join(_taken.mappedBy((b) => b.toString()), ",");
  
  _log(message) => print("table: $message");
  
  _whenInit(message, _) {
    assert(message is InitTable);
    this._n = message.n;
    _taken = new List.filled(_n, false);
    _log("placing philosophers ...");
    for (int i=0; i< _n; i++) {
      var p = spawnFunction(philosopher);
      p.send(new InitPhilosopher(i, port.toSendPort()));
      _philosophers.add(p);
    }    
    _log("starting to dine ...");
    _philosophers.forEach((p) => p.send(new StartDinner()));    
    _state = STATE_ACTING;
  }
  
  _whenActing(message, replyTo) {
    if (message is AcquireChopsticks) {
      var p = message.philosopher;
      var left = p;
      var right = (p + _n -1) % _n;
      if (!_taken[left] && !_taken[right]) {
        _taken[left] = true;
        _taken[right] = true;
        _log("philo $p: granting both chopsticks ...");
        replyTo.send(true);
      } else {
        replyTo.send(false);
      }
    } else if (message is ReleaseChopsticks) {
      _taken[message.philosopher] = false;
      _taken[(message.philosopher + _n -1) % _n] = false;
      _log("philo ${message.philosopher}: released chopsticks ...");
      _notifyChopstickAvailable();
    }
  }    
  
  /// notifies all philosophers that chopsticks are available
  _notifyChopstickAvailable() {
    _philosophers.forEach((p) => p.send(new NotifyChopsticksAvailable()));
  }
}

table() => new Table();

/**
 * Message to initialize a philosopher 
 */
class InitPhilosopher {
  /// the philosopher id 
  final int i;
  /// the port of the table isolate 
  final SendPort table;
  InitPhilosopher(this.i, this.table);
}

/// Message sent to philosophers to start the dinner 
class StartDinner{}

/**
 * An instance of Philosopher represents a thinking and eating philosopher.
 * 
 */
class Philosopher {
  static const STATE_INIT = 0;
  static const STATE_ACTING = 1;
  
  var _i;
  var _table;
  var _state = STATE_INIT;
  
  // in STATE_WAITING_FOR_CHOPSTICKS a philosopher wait for the
  // completion of the future of this completer. 
  var _chopstickAvailCompleter = null;
  
  Philosopher() {
    port.receive((message, replyTo) {
      switch(_state) {
        case STATE_INIT: _whenInit(message, replyTo); break;
        case STATE_ACTING: _whenActing(message, replyTo); break;
      }
    });
  }
  
  _log(message) => print("philosopher $_i: $message");
  
  _whenInit(message, _) {
    assert(message is InitPhilosopher);
    this._i = message.i;
    this._table = message.table;
    _state = STATE_ACTING;
  }
  
  _whenActing(message, _) {
    if (message is StartDinner) {
      _thinkThenEat();
    }
    else if (message is NotifyChopsticksAvailable) {        
      if (_chopstickAvailCompleter != null) {
        // this will trigger the next attempt to acquire
        // chopsticks, see _acquireChopsticks below 
        _chopstickAvailCompleter.complete(null);
      }
    } 
  }
  
  _thinkThenEat() {
    _think() 
    .then((_) {
        _log("acquire chopsticks ... START");
        return _aquireChopsticks();
    })
    .then((_) => _eat())
    .then((_) => _releaseChopsticks())
    .then((_) => _thinkThenEat());
  }
  
  /// the returned future is completed upon the
  /// next received [NotifyChopsticksAvailable] message.
  Future _waitForChopstickAvailNotification() {   
    _chopstickAvailCompleter = new Completer();      
    return _chopstickAvailCompleter.future;
  }
    
  /// completes with value null when usage of both
  /// chopsticks is granted 
  Future _aquireChopsticks() {
    var completer = new Completer();
    _table.call(new AcquireChopsticks(_i)).then((result) {
      if (result) {
        _log("acquire chopsticks ... DONE");
        completer.complete(null);
        return;
      } 
      // we don't poll after a random delay, but wait for
      // a notification from the table, that free chopsticks
      // are available
      _waitForChopstickAvailNotification()
      .then((_) {
        _log("got notified - trying to acquire again");
        _chopstickAvailCompleter = null;    
        return _aquireChopsticks();
      })
      .then((_) => completer.complete(null));
    });
    return completer.future;
  }
  
  /// completes with value null when both chopsticks are released 
  Future _releaseChopsticks() {
    _log("releasing chopsticks ...");
    _table.send(new ReleaseChopsticks(_i));
    return new Future.immediate(null);
  }
  
  /// completes with value null when thinking is over
  Future _think(){
    _log("thinking ...");
    return _sleepRandom(2000);
  }
  
  /// completes with value null when eating is over 
  Future _eat() {
    _log("eating  ...");
    return _sleepRandom(2000);
  }
}

philosopher() => new Philosopher();

dine(n) {
  assert(n >= 2);
  var actTable = spawnFunction(table);
  actTable.send(new InitTable(n));
}