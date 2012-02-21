%%----------------------------------------------------------------------------------------------------------------------------------------
%% ct_surefire
%%
%% Copyright (c) 2011 Martin Scholl (ms@funkpopes.org)
%% Copyright (c) 2011 global infinipool GmbH
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files
%% (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge,
%% publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
%% subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
%% MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
%% ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
%% THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%%----------------------------------------------------------------------------------------------------------------------------------------
%% @author Martin Scholl <ms@funkpopes.org>
%% @author Jean R. Mavi <jmavi21@yahoo.com>
%% @doc
%%     A utility Erlang library that converts Common Test's suite.log.html output file(s) into a Surefire XML report
%% @end
%% @copyright
%%     2011 Martin Scholl, 2011 global infinipool GmbH
%% @end
%% @type error_tuple() = {error, Reason :: term()}.
%% @type ok_tuple() = {ok, Value :: term()}.
%%----------------------------------------------------------------------------------------------------------------------------------------
-module(ct_surefire).
-compile([{parse_transform, do}]).

%% API (v0.3)
-export([to_surefire_xml/1, to_surefire_xml/2]).
%% API (v0.4)
-export([generate_surefire_reports/1, generate_surefire_reports/2]).

%%========================================================================================================================================
%% API (version 0.3)
%%========================================================================================================================================
%% @spec to_surefire_xml(Args :: list()) -> ok | error_tuple()
%% @equiv generate_surefire_reports(hd(Args), hd(tl(Args)))
%% @doc This function is called when running ct_surefire from the command line using the -run option
to_surefire_xml([CtLogDir, OutputDir]) ->
    generate_surefire_reports(CtLogDir, OutputDir);

to_surefire_xml(_) ->
    error(badarg).

%% @spec to_surefire_xml(CtLogDir :: string(), OutputDir :: string()) -> ok | error_tuple()
%% @equiv generate_surefire_reports(CtLogDir, OutputDir)
to_surefire_xml(CtLogDir, OutputDir) ->
    generate_surefire_reports(CtLogDir, OutputDir).

%%========================================================================================================================================
%% API (version 0.4)
%%========================================================================================================================================
%% @spec generate_surefire_reports(Args :: list()) -> ok | error_tuple()
%% @equiv generate_surefire_reports(CtLogDir, OutputDir)
%% @doc This function is called when running ct_surefire from the command line using the -run option
generate_surefire_reports([CtLogDir, OutputDir]) ->
    generate_surefire_reports(CtLogDir, OutputDir);

generate_surefire_reports(_) ->
    error(badarg).

%% @spec generate_surefire_reports(CtLogDir :: string(), OutputDir :: string()) -> ok | error_tuple()
%% @doc Parses and translates Common Test HTML logs from the log directory then writes the corresponding Surefire XML report in the output directory
generate_surefire_reports(CtLogDir, OutputDir) ->
    do([error_m ||
        validate_directory(CtLogDir),
        validate_directory(OutputDir),
        HtmlLogFiles <- get_latest_reports(CtLogDir),
        ParsedReports <- parse_reports(CtLogDir, HtmlLogFiles),
        write_reports(OutputDir, ParsedReports)
    ]).

%%========================================================================================================================================
%% Internal functions (reports)
%%========================================================================================================================================
%% @spec get_latest_reports(CtLogDir :: string()) -> ok_tuple() | error_tuple()
%% @doc Given the Common Test log directory as the base directory, return a list of relative paths to the most recent suite.log.html files
get_latest_reports(CtLogDir) ->
    % used just a single filelib:wildcard/2 call here so we don't have to do a validate_directory/1 or file_lib:is_dir/1 multiple times
    HtmlLogFiles = filelib:wildcard(filename:join(["ct_run.*", "*.logs", "run.*", "suite.log.html"]), CtLogDir),

    case lists:reverse(lists:sort(HtmlLogFiles)) of
        [] ->
            {error, no_test_case_dirs_found};
        [LatestHtmlLogFile | _] ->
            [LatestTestRunDir, _, _, "suite.log.html"] = filename:split(LatestHtmlLogFile),
            {ok, [LogFile || LogFile <- HtmlLogFiles, LatestTestRunDir =:= hd(filename:split(LogFile))]}
    end.

%% @spec parse_reports(CtLogDir :: string(), LogFiles :: [string()]) -> ok_tuple() | error_tuple()
%% @doc Given the Common Test log directory as the base directory and a list of relative paths to the most recent suite.log.html files,
%%     returns the successfully-parsed representations of the Common Test results
parse_reports(CtLogDir, LogFiles) ->
    ParsedReports = lists:foldl(fun(LogFile, Results) ->
        [_, TestRunDir, _, "suite.log.html"] = filename:split(LogFile),
        [_, AppName | _] = string:tokens(TestRunDir, "."),

        case ct_suite_log_parser:file(filename:join([CtLogDir, LogFile])) of
            {ok, {Elapsed, Failed, Skipped, TestCases}} ->
                [{AppName, Elapsed, Failed, Skipped, TestCases} | Results];
            _ ->
                Results
        end
    end, [], LogFiles),

    case ParsedReports of
        [] ->
            {error, ct_report_not_found};
        _ ->
            {ok, ParsedReports}
    end.

%% @spec write_reports(CtLogDir :: string(), [report()]) -> ok
%% @doc Given the Output directory and the list of Common Test results, writes the corresponding Surefire XML report(s)
write_reports(OutputDir, [{AppName, Elapsed, Failed, Skipped, TestCases} | Reports]) ->
    OutputFile = filename:join([OutputDir, "TEST-" ++ AppName ++ "_ct.xml"]),

    XmlHeader = io_lib:format("<?xml version=\"1.0\" encoding=\"UTF-8\" ?>~n<testsuite tests=\"~p\" failures=\"~p\" errors=\"0\" skipped=\"~p\" time=\"~s\" name=\"common_test '~s'\">~n", [
		length(TestCases), Failed, Skipped, Elapsed, AppName
	]),

    XmlBody = lists:map(fun({TestCaseId, TestSuiteModule, TestCaseFunction, Duration, ok}) ->
        io_lib:format("    <testcase name=\"~s:~s/0_~s\" time=\"~s\" />~n", [
            TestSuiteModule, TestCaseFunction, TestCaseId, Duration
        ]);
    ({TestCaseId, TestSuiteModule, TestCaseFunction, Duration, {failed, Reason}}) ->
        io_lib:format("    <testcase name=\"~s.~s/0_~s\" time=\"~s\">~n        <error type=\"error\">~s</error>~n        <system-out />~n    </testcase>~n", [
            TestSuiteModule, TestCaseFunction, TestCaseId, Duration, Reason
        ]);
    ({TestCaseId, TestSuiteModule, TestCaseFunction, Duration, {skipped, _Reason}}) ->
        io_lib:format("    <testcase name=\"~s:~s/0_~s\" time=\"~s\" >~n        <skipped />~n    </testcase>", [
            TestSuiteModule, TestCaseFunction, TestCaseId, Duration
        ])
    end, TestCases),

    XmlFooter = "</testsuite>",

    file:write_file(OutputFile, XmlHeader ++ XmlBody ++ XmlFooter),

    write_reports(OutputDir, Reports);

write_reports(_, []) ->
    ok.

%%========================================================================================================================================
%% Internal functions (validation)
%%========================================================================================================================================
%% @spec validate_directory(Directory :: term()) -> ok | error_tuple()
%% @doc If Directory is a string reference to an actual directory, returns ok; otherwise, returns an error tuple
validate_directory(Directory) when false =:= is_list(Directory); [] =:= Directory ->
    {error, {invalid_directory, [
        {directory, Directory}
    ]}};

validate_directory(Directory) ->
    case filelib:is_dir(Directory) of
        true ->
            ok;
        _ ->
            {error, {invalid_directory, [
                {directory, Directory}
            ]}}
    end.
