library dinner5.cmd;

import "dart:isolate";
import "package:args/args.dart";
import "dart:io";

import "package:dining_philosophers/dinner5.dart" as dinner5;

main() {
  var parser = new ArgParser();
  parser.addOption("num-philosophers", abbr: "n", defaultsTo: "5",
      help: "the number of philosophers [n >= 2]");
  parser.addFlag("help", abbr: "h", negatable: false, help: "display help");
  var options = parser.parse(new Options().arguments);
  if (options["help"]) {
    print("usage: dart dinner5.dart");
    print(parser.getUsage());
    exit(0);
  }

  var n = int.parse(options["num-philosophers"], onError: (source) {
    print("fatal: '$source' isn't a valid integer");
    exit(1);
  });
  if (n < 2) {
    print("fatal: ${options["num-philosophers"]} isn't a number >= 2");
    exit(1);
  }
  print("*");
  print("* Dining philosophers, Dijkstras aproach with resource ordering");
  print("*");
  print("Starting a dinner with $n philosophers ...");
  dinner5.dine(n);
  port;
}
