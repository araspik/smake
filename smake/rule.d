/**** Rule: A basic rule to execute.
  * 
  * Rules consist of commands to execute, along with a (optional) set of inputs
  * and outputs.
  * 
  * Author: ARaspiK
  * License: MIT
  */
module smake.rule;

import std.datetime;
import std.file;
import std.typecons;

import sdlang;

/// A basic rule to execute.
struct Rule {
	/// Name of rule.
	string name;
	/// Commands to run.
	string[] commands;
	/// Input and output file names.
	string[] inputs, outputs;

	/// Whether the rule is invalid (true) or not.
	@property bool invalid() const {
		import std.algorithm: canFind;
		import std.functional: memoize;

		return memoize!(() => inputs.canFind!(i => !i.exists))();
	}

	/// Input modification times.
	@property Nullable!(SysTime[]) inputTimes() const {
		import std.algorithm: map;
		import std.array: array;
		import std.functional: memoize;

		return memoize!(() => invalid
				? Nullable!(SysTime[])()
				: inputs.map!timeLastModified.array.nullable)();
	}

	/// Latest input modification time.
	@property Nullable!SysTime lastInputMod() const {
		import std.algorithm: maxElement;
		import std.functional: memoize;

		return memoize!(() => inputTimes.apply!maxElement)();
	}

	/// Whether an update is needed or not.
	@property Nullable!bool updateNeeded() const {
		import std.algorithm: canFind;
		import std.functional: memoize;

		return memoize!(() => lastInputMod.apply!(m => outputs
					.canFind!(o => !o.exists || o.timeLastModified < m)))();
	}

	/**** Returns verbose information about update requirements.
		* 
		* The information is returned as a lazy range of output-update information.
		* Each element represents one output.
		* The properties of each element are:
		* * `.output`: Name of output file.
		* * `.needsUpdate`: Whether the output needs to be updated.
		* * `.exists`: Whether the file exists.
		* * `.input`: An input file which the output is older than.
		*             If this doesn't make sense then it is 'null', which occurs
		*             when the output is newer than all input files or it just
		*             doesn't exist at all.
		* * `.toString`: A human-readable string output.
		* 
		*/
	auto getUpdateInfo() const {
		// The output struct we use
		static struct OutputUpdateInfo {
			string output;
			string input;
			bool needsUpdate;
			bool exists;

			string toString() const {
				import std.format;

				if (!exists)
					return output.format!`"%s" nonexistent, needs update.`;
				else if (needsUpdate)
					return output.format!`"%s" is older than "%s", needs update.`(input);
				else
					return output.format!`"%s" is newest, does not need update.`;
			}
		}

		import std.algorithm: map;

		return outputs.map!((o) {
			import std.algorithm: countUntil;

			OutputUpdateInfo res = OutputUpdateInfo(o, null, true, o.exists);

			if (!res.exists) {}
			else if (auto j = inputTimes.countUntil!"a > b"(o.timeLastModified) + 1)
				res.input = inputs[j-1];
			else
				res.needsUpdate = false;

			return res;
		});
	}

	/// Stringifier.
	string toString() const {
		import std.format;

		return format!`{%(%s%| %)} -> {%(%s%| %)} via {%(%s%|, %)} (%s)`
			(inputs, outputs, commands, updateNeeded
			 .apply!(n => (n ? "needs" : "does not need") ~ " update").get("invalid!"));
	}

	/// Verbose stringifier.
	string toString(bool verbose) const {
		import std.format;

		if (verbose && !invalid)
			return toString ~ getUpdateInfo.format!"%-(\n* %s%)";
		else
			return toString;
	}

	/// Reads from a SDLang Tag.
	/// Returns nonexistent if parsing failed.
	static Nullable!Rule parse(Tag tag) {
		import std.algorithm;
		import std.array;
		import std.range;

		if (tag.name != "rule"
				|| tag.values.length != 1
				|| tag.values[0].peek!string is null)
			return typeof(return)();

		string name = tag.values[0].get!string;

		string[] cmds = tag.tags
			.filter!(t => t.name == "cmd")
			.map!(t => t.values
				.map!(v => v.peek!string !is null ? v.get!string : null))
			.join;

		if (!cmds.length)
			return typeof(return)();

		string[] inputs = tag.tags
			.filter!(t => t.name == "in")
			.map!(t => t.values
					.map!(v => v.peek!string !is null ? v.get!string : null))
			.join;

		string[] outputs = tag.tags
			.filter!(t => t.name == "out")
			.map!(t => t.values
					.map!(v => v.peek!string !is null ? v.get!string : null))
			.join;

		return chain(cmds, inputs, outputs).canFind(null)
			? typeof(return)()
			: Rule(name, cmds, inputs, outputs).nullable;
	}
}
