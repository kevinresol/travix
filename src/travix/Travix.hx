package travix;

import haxe.DynamicAccess;
import haxe.Json;
import sys.FileSystem;
import haxe.ds.Option;
import sys.io.*;
import Sys.*;

using StringTools;
using haxe.io.Path;
using sys.FileSystem;
using sys.io.File;

#if macro
import haxe.macro.MacroStringTools;
import haxe.macro.Context;
#end

enum RunResult {
  Success(output:String);
  Failure(code:Int, output:String);
}

class Travix {
  static inline var PROFILE = 'https://travis-ci.org/profile/';
  static inline var TESTS = 'tests.hxml';
  
  static inline var DEFAULT_PLATFORMS = 'interp, neko, node, python, java';
  static inline var ALL = 'interp,neko,python,node,flash,java,cpp,cs,php';
  
  static inline var TRAVIS_CONFIG = '.travis.yml';
  static inline var HAXELIB_CONFIG = 'haxelib.json';
  
  function new() { }
  
  function enter(what:String, def:String) {
    println('Please specify $what (default: $def):');
    return switch Sys.stdin().readLine().trim() {
      case '': def;
      case v: v;
    }
  }
  
  function ask(question:String) {
    while (true) {
      print('$question (y/n)? ');
      var c = Sys.getChar(true);
      println('');
      switch String.fromCharCode(c).toUpperCase() {
        case 'Y': return true;
        case 'N': return false;
        default:
      }
    }
    
    return throw 'unreachable';
  }
  function makeYml() {
    if (TRAVIS_CONFIG.exists() && !ask('The $TRAVIS_CONFIG is already present. Do you wish to replace it with a new one')) return;
    
    var platforms = [for (p in enter('platforms as a comma-separated list or `all`', DEFAULT_PLATFORMS).split(',')) 
        switch p.trim() {
          case '': continue;
          case v: v;
        }
    ];
    
    if (platforms.remove('all'))
      platforms = ALL.split(',');
    
    TRAVIS_CONFIG.saveContent(defaultFile());
  }
  
  function makeJson() {
    if (HAXELIB_CONFIG.exists()) return;
    
    function defaultClassPath() {
      for (option in 'src,hx'.split(','))
        if (option.exists()) return './$option';
      return '.';
    }
    
    var infos:Infos = {
      name: enter('library name', Sys.getCwd().removeTrailingSlashes().withoutDirectory()),
      classPath: enter('classpath', defaultClassPath()),
      dependencies: {}
    }
    
    HAXELIB_CONFIG.saveContent(Json.stringify(infos, '  '));
  }
  
  function doInit() {
    
    makeYml();
    makeJson();
    
    if (!TESTS.exists()) {
      println('no $TESTS found');
      
      var cp = enter('class path for tests', './tests/');
      var main = 'RunTests';
      
      for (m in 'Run,Main'.split(',')) 
        if ('$cp/$m.hx'.exists()) {
          main = m;
          break;
        }
        
      main = enter('test entry point', main);
      
      TESTS.saveContent([
        '-cp $cp',
        '-main $main',
      ].join('\n'));
      
      if (ask('Activate CI for this project now'))      
        switch Sys.systemName() {
          case 'Windows':
            exec('start', [PROFILE]);
          case 'Linux':
            exec('xdg-open', [PROFILE]);
          case 'Mac':
            exec('open', [PROFILE]);
          default:
            println('Unknown OS. Please go to $PROFILE');
        }
    }
  }
  
  macro static function defaultFile() {
    return MacroStringTools.formatString(File.getContent(Context.getPosInfos((macro null).pos).file.directory() + '/default.yml'), Context.currentPos());
  }
  
  function tryToRun(cmd:String, ?params:Array<String>) 
    return try {
      var p = new Process(cmd, params);
      switch p.exitCode() {
        case 0:
          Success(switch p.stdout.readAll().toString() {
            case '': p.stderr.readAll().toString(); //some execs print to stderr
            case v: v;
          });
        case v:
          Failure(v, p.stderr.readAll().toString());
      }
    } catch (e:Dynamic) {
      Failure(404, 'Unknown command $cmd'); 
    }
  
  function run(cmd:String, ?params:Array<String>) {
    var a = [cmd];
    if (params != null)
      a = a.concat(params);
      
    print('> ${a.join(" ")} ...');
    return
      switch tryToRun(cmd, params) {
        case Success(v): 
          println(' done');
          v;
        case Failure(code, out):
          println(' failure');
          print(out);
          exit(code);
          throw 'unreachable';
      }
  }
  
  function libInstalled(lib:String) 
    return tryToRun('haxelib', ['path', lib]).match(Success(_));
  
  function installLib(lib:String, ?version = '') {
    
    if (!libInstalled(lib))
      switch version {
        case null | '':
          exec('haxelib', ['install', lib, '--always']);
        default:
          exec('haxelib', ['install', lib, version, '--always']);
      }
      
  }
  
  function die(message:String, ?code = 500):Dynamic {
    println(message);
    exit(code);
    return null;
  }
  
  function doInstall() {
    
    if (!TESTS.exists())
      die('$TESTS not found');
    
    var info = getInfos();
    
    run('haxelib', ['dev', info.name, '.']);
    
    switch info.dependencies {
      case null:
      case v:
        
        for (lib in v.keys())
          installLib(lib, v[lib]);
    }
    run('haxelib', ['install', TESTS, '--always']);  
    
    exec('haxelib', ['list']);
  }
  
  function getInfos():Infos
    return haxe.Json.parse(File.getContent(HAXELIB_CONFIG));
  
  function classPath()
    return switch getInfos().classPath {
      case null: '.';
      case v: v;
    }    
  
  function build(args:Array<String>) {
    
    exec('haxe', ['-lib', getInfos().name, 'tests.hxml'].concat(args));
    //run('haxe', ['-lib', getInfos().name, 'tests.hxml'].concat(args));
    
  }
  
  function aptGet(pckge:String, ?args:Array<String>) {
    switch Sys.systemName() {
      case 'Linux':
        exec('sudo', ['apt-get', 'install', '-qq', pckge].concat(if (args == null) [] else args));
      case v:
        println('Cannot run apt-get on $v');
    }  
  }
      
  function exec(cmd, ?args) {
    var a = [cmd];
    if (args != null)
      a = a.concat(args);
    println('> ' + a.join(' '));
    switch command(cmd, args) {
      case 0: 
      case v: exit(v);
    }
  }
  
  function getMainClass() {
    
    function read(file:String) {
      for (line in file.getContent().split('\n').map(function (s:String) return s.split('#')[0].trim())) 
        if (line.startsWith('-main'))
          return Some(line.substr(5).trim());
        else
          if (line.endsWith('.hxml'))
            switch read(line) {
              case None:
              case v: return v;
            }
            
      return None;
    }
    return switch read(TESTS) {
      case Some(v): v;
      default: die('no -main class found in $TESTS');
    }
  }
  
  function doPhp() {
    build(['-php', 'bin/php']);
    
    if (tryToRun('php', ['--version']).match(Failure(_, _)))
      aptGet('php5');
      
    exec('php', ['bin/php/index.php']);
  }
  
  function doInterp() {
    build(['--interp']);
  }
  
  function doJava() {
    
    var main = getMainClass();
    
    installLib('hxjava');
    
    build(['-java', 'bin/java']);
    
    exec('java', ['-jar', 'bin/java/$main.jar']);
  }
  
  function withCwd<T>(dir:String, f:Void->T) {
    var old = getCwd();
    setCwd(dir);
    var ret = f();
    setCwd(old);
    return ret;
  }
  
  function doCpp() {
    
    var main = getMainClass();
    
    if (Sys.getEnv('TRAVIS_HAXE_VERSION') == 'development') {
      
      aptGet('gcc-multilib');
      aptGet('g++-multilib'); 
      
      if (!libInstalled('hxcpp')) {
        exec('haxelib', ['git', 'hxcpp', 'https://github.com/HaxeFoundation/hxcpp.git']);
        withCwd(run('haxelib', ['path', 'hxcpp']).split('\n')[0], buildHxcpp);
      }      
    }
    else installLib('hxcpp');
    
    build(['-cpp', 'bin/cpp']);
    
    exec('./bin/cpp/$main');
  }
  
  function buildHxcpp() {
    withCwd('tools/hxcpp', exec.bind('haxe', ['compile.hxml']));
    withCwd('project', exec.bind('neko', ['build.n']));
    
  }
  
  function doCs() {
    
    var isWindows = Sys.systemName() == 'Windows';
    
    if (!isWindows)
      if (tryToRun('mono', ['--version']).match(Failure(_, _))) {
        aptGet('mono-devel');
        aptGet('mono-mcs');
      }
      
    var main = getMainClass();
    
    installLib('hxcs');
    
    build(['-cs', 'bin/cs/']);
    
    if (isWindows)
      exec('bin/cs/bin/$main.exe'.replace('/', '\\'));
    else
      exec('mono', ['bin/cs/bin/$main.exe']);
  }
  
    
  function doNeko() {
    build(['-neko', 'bin/neko/tests.n']);
    exec('neko', ['bin/neko/tests.n']);
  }
  
  function doPython() {
    build(['-python', 'bin/python/tests.py']);
    exec('python3', ['bin/python/tests.py']);
  }
  
  function doFlash() {
    build(['-swf', 'bin/swf/tests.swf']);
  }
  
  function doNode() {
    
    installLib('hxnodejs');
    
    build(['-js', 'bin/node/tests.js', '-lib', 'hxnodejs']);
    exec('node', ['bin/node/tests.js']);    
  }  
  
  function doHelp() {
    println('Commands');
    println('  ');
    println('  init - initializes a project with a .travis.yml');
    println('  install - installs dependencies');
    println('  interp - run tests on interpreter');
    println('  neko - run tests on neko');
    println('  node - run tests on nodejs (with hxnodejs)');
    println('  php - run tests on php');
    println('  java - run tests on java');
    println('  flash - compiles tests on flash');
    println('  python - run tests on python');
    println('  cs - run tests on cs');
    println('  cpp - run tests on cpp');
  }
  
  static function main() {
    
    var args = Sys.args();
    
    #if interp
      Sys.setCwd(args.pop());
    #end
    
    var url = 
      switch args.shift() {
        case null: 'help';
        case v: v;
      }
      
    var params = new Map(),
        value = '';
    
    for (a in args) {
      
      if (a.startsWith('-')) {
        params[a.substr(1)] = value;
        value = '';
      }
      else value = a;
      
    }
    
    var t = new Travix();
    
    haxe.web.Dispatch.run(url, params, t);
  }
  
}

private typedef Infos = { 
  name: String, 
  ?dependencies:DynamicAccess<String>,
  ?classPath: String,
}