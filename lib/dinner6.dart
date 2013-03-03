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
 * Philosophers are initialized with IsolateSinks of their
 * left and right fork. Before they start dining, they listen to the
 * the ids of this forks. A philosopher always picks up the
 * fork with the lower id first. He releases forks in opposite
 * order.
 *
 * In constrast to dinner5, this solutions uses streams, not ports,
 * to communicate between isolates.
 */

import "dart:isolate";
import "dart:math";
import "dart:async";

var _random = new Random();

/// completes after [delay] ms with value null
Future sleep(delay) => new Future.delayed(
    new Duration(milliseconds:delay), ()=>null);

/// completes after a random number of `ms` in the range
/// 0..[range] with value null
Future sleepRandom(range) => sleep(_random.nextInt(range));


/// initializes the table with the number of philosophers
class InitTable {
  /// the number of philosophers. n>=2 expected.
  final int n;
  InitTable(this.n) {
    assert(n >= 2);
  }
}

/// message to initialize a fork
class InitFork {
  final int id;
  InitFork(this.id);
}

class PickUp{}
class PutDown{}
class QueryId {}

/**
 * Represents a fork on the diner table.
 */
class Fork {

  bool inUse = false;
  int id;
  StreamSink pending = null;
  StreamSubscription currentHandler;

  Fork() {
    currentHandler = stream.listen(handleInit);
  }

  /// handles messages when in state 'init'
  handleInit(message) {
    assert(message is InitFork);
    this.id = message.id;
    currentHandler.cancel();
    currentHandler = stream.listen(handleRequest);
    log("initialized");
  }

  /// handles messages after the initialization phase
  handleRequest(message) {
    var replyTo = null;
    if (message is Map) {
      replyTo = message["replyTo"];
      message = message["message"];
    }
    if (message is PickUp) {
      if (inUse) {
        log("pickup: already in use - remember request");
        pending = replyTo;
      } else {
        log("pickup: not in used yet - grant request");
        inUse = true;
        replyTo.add(true);
      }
    } else if (message is PutDown) {
      assert(inUse);
      if (pending != null) {
        log("putDown: grant to pending request");
        pending.add(true);
        pending = null;
      } else {
        log("putDown: free again");
        inUse = false;
      }
      replyTo.add("done");
    } else if (message is QueryId) {
      log("query id ...");
      replyTo.add(id);
    }
  }

  log(m) => print("fork $id: $m");
}

fork() => new Fork();

/// message sent to initialize a philosopher
class InitPhilosopher {
  final int id;
  final List<IsolateSink> forks;
  InitPhilosopher(this.id, this.forks);
}

/// message sent to start the dinner
class StartDinner{}


class Philosopher {
  int id;
  List forks;

  StreamSubscription currentHandler;

  /**
   * A simulation of SendPort.call using streams and
   * one-shot message box
   */
  Future call(IsolateSink sink, message){
    var mb = new MessageBox.oneShot();
    var completer = new Completer();
    sink.add({"replyTo": mb.sink, "message" : message});
    mb.stream.listen((reply) => completer.complete(reply));
    return completer.future;
  }

  Philosopher() {
    currentHandler = stream.listen(handleInit);
  }

  /// responds to messages when in 'init' state
  handleInit(message) {
    if(message is InitPhilosopher) {
      id = message.id;
      forks = [];
      Future.forEach(message.forks, (f) {
        return call(f, new QueryId()).then((id) {
          forks.add({"id": id, "fork": f});
        });
      })
      .then((_) {
        forks.sort((a,b) => a["id"].compareTo(b["id"]));
        var fids = forks.map((f)=>f["id"]).join(",");
        log("init - forks: $fids");
      });
    } else if (message is StartDinner) {
      thinkAndEat();
    }
  }

  thinkAndEat() {
    think()
    .then((_) => pickUpForks())
    .then((_) => eat())
    .then((_) => putDownForks())
    .then((_) => thinkAndEat());
  }

  Future think() {
    log("thinking ...");
    return sleepRandom(2000);
  }

  Future eat() {
    log("eating ...");
    return sleepRandom(2000);
  }

  Future pickUpForks() {
    log("picking up forks ... START");
    return call(forks[0]["fork"], new PickUp())
    .then((_) {
      log("pick up: got fork ${forks[0]["id"]}");
      return call(forks[1]["fork"], new PickUp());
    }).then((_) {
      log("pick up: got fork ${forks[1]["id"]}");
      return new Future.immediate(null);
    });
  }

  Future putDownForks() {
    log("putting down forks ...");
    var msg = new PutDown();
    return call(forks[1]["fork"], msg)
        .then((_) => call(forks[0]["fork"], msg));
  }

  log(m) => print("philosopher $id: $m");
}

philosopher() => new Philosopher();


class Table {
  var philosophers = [];
  var forks = [];
  int n;

  Table(this.n) {
    initForks();
    initPhilosophers();
  }

  initForks() {
    for (int i=0; i<n; i++) {
      forks.add(streamSpawnFunction(fork));
      forks[i].add(new InitFork(i));
    }
  }

  initPhilosophers() {
    for (int i=0; i<n; i++) {
      philosophers.add(streamSpawnFunction(philosopher));
      var forks = [this.forks[i], this.forks[(i + n -1) % n]];
      philosophers[i].add(new InitPhilosopher(i, forks));
    }
  }

  dine() {
    var msg = new StartDinner();
    philosophers.forEach((p) => p.add(msg));
  }
}

dine(int n) {
  var table = new Table(n);
  table.dine();
}



