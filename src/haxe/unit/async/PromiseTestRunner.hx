package haxe.unit.async;

#if nodejs
import js.Node;
#end

import haxe.rtti.Meta;

import promhx.Deferred;
import promhx.Promise;

using Lambda;
using StringTools;

typedef TestResult = {
	var run :Int;
	var passed :Int;
}

class PromiseTestRunner
{
	public var onFinish :Void->Void;

	public function new() :Void {}

	public function setDefaultTimeout(milliseconds :Int)
	{
		_defaultTestTimeout = milliseconds;
		return this;
	}

	public function add(testObject :PromiseTest) :PromiseTestRunner
	{
		_tests.push(testObject);
		return this;
	}

	public function run()
	{
		var success = true;
		var doTest = null;
		var totalTestsRun = 0;
		var totalTestsPassed = 0;
		doTest = function() {
			if (_tests.length == 0) {
				trace('TOTAL TESTS PASSED ${totalTestsPassed} / ${totalTestsRun}');
				try {
					if (onFinish != null) {
						onFinish();
					}
				} catch (err :Dynamic) {
					trace(err);
				}
#if nodejs
				Node.process.exit(success ? 0 : 1);
#else
				Sys.exit(success ? 0 : 1);
#end
			} else {
				var testObj = _tests.shift();
				if (testObj == null) {
					doTest();
				} else {
					var promise = runTestsOn(testObj)
						.then(function(result :TestResult) {
							totalTestsRun += result.run;
							totalTestsPassed += result.passed;
							if (result.run < result.passed) {
								success = false;
							}
							doTest();
						});
				}
			}
		}
		doTest();
		return this;
	}

	function runTestsOn(testObj :PromiseTest) :Promise<TestResult>
	{
		var className = Type.getClassName(Type.getClass(testObj));
		var deferred = new Deferred();
		var promise = deferred.promise();

		var run = 0;
		var passed = 0;

		var nextTest = null;
		nextTest = function(testMethodNames :Array<String>) {
			if (testMethodNames.length == 0) {
				trace("Passed " + passed + " / " + run + " " + className);
				deferred.resolve({'run':run, 'passed' :passed});
			} else {
				var fieldName = testMethodNames.shift();

				var timeout = _defaultTestTimeout;
				var fieldMetaData = Reflect.field(Meta.getFields(Type.getClass(testObj)), fieldName);
				if (fieldMetaData != null && Reflect.hasField(fieldMetaData, 'timeout')) {
					timeout = Reflect.field(fieldMetaData, 'timeout');
				}

				run++;
				var setupPromise :Null<Promise<Bool>> = testObj.setup();
				setupPromise = setupPromise == null ? Promise.promise(true) : setupPromise;
				setupPromise
					.pipe(function(isSetup :Bool) {
						var result :Promise<Bool> = Reflect.callMethod(testObj, Reflect.field(testObj, fieldName), []);
						if (result == null) {
							result = Promise.promise(true);
						}
						haxe.Timer.delay(function() {
							if (!result.isResolved()) {
								result.reject('Timeout');
							}
						}, timeout);
						return result;
					})
					.pipe(function(didPass :Bool) {
						if (didPass) {
							passed++;
							trace(".....Success....." + fieldName);
						} else {
							trace(".....FAILED......" + fieldName);
						}
						var tearDown :Null<Promise<Bool>> = testObj.tearDown();
						return tearDown == null ? Promise.promise(true) : tearDown;
					})
					.then(function(didTearDown :Bool) {
						nextTest(testMethodNames);
					})
					.errorThen(function(err :Dynamic) {
						trace(".....FAILED......" + fieldName);
						trace(err);
						nextTest(testMethodNames);
					});
			}
		}

		nextTest(Type.getInstanceFields(Type.getClass(testObj)).filter(function(s) return s.startsWith("test")));

		return promise;
	}

	var _tests :Array<PromiseTest> = [];
	var _defaultTestTimeout :Int = 60;
}