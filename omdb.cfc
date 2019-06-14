component {
	cfprocessingdirective( preserveCase=true );

	function init(
		required string apiKey
	,	string apiUrl= "http://www.omdbapi.com"
	,	string apiVersion= 1
	,	numeric throttle= 0
	,	numeric httpTimeOut= 60
	,	boolean debug= ( request.debug ?: false )
	) {
		this.apiKey= arguments.apiKey;
		this.apiUrl= arguments.apiUrl;
		this.apiVersion= arguments.apiVersion;
		this.httpTimeOut= arguments.httpTimeOut;
		this.throttle= arguments.throttle;
		this.debug= arguments.debug;
		this.lastRequest= server.omdb_lastRequest ?: 0;
		this.config= {};
		return this;
	}

	function debugLog( required input ) {
		if ( structKeyExists( request, "log" ) && isCustomFunction( request.log ) ) {
			if ( isSimpleValue( arguments.input ) ) {
				request.log( "OMDb: " & arguments.input );
			} else {
				request.log( "OMDb: (complex type)" );
				request.log( arguments.input );
			}
		} else if( this.debug ) {
			cftrace( text=( isSimpleValue( arguments.input ) ? arguments.input : "" ), var=arguments.input, category="OMDb", type="information" );
		}
		return;
	}

	struct function apiRequest( required string api ) {
		arguments[ "apikey" ]= this.apiKey;
		arguments[ "v" ]= this.apiVersion;
		arguments[ "r" ]= "json";
		var http= {};
		var item= "";
		var out= {
			args= arguments
		,	success= false
		,	error= ""
		,	status= ""
		,	statusCode= 0
		,	response= ""
		,	verb= listFirst( arguments.api, " " )
		,	requestUrl= ""
		,	data= {}
		};
		out.requestUrl &= listRest( out.args.api, " " );
		structDelete( out.args, "api" );
		// replace {var} in url 
		for ( item in out.args ) {
			// strip NULL values 
			if ( isNull( out.args[ item ] ) ) {
				structDelete( out.args, item );
			} else if ( isSimpleValue( arguments[ item ] ) && arguments[ item ] == "null" ) {
				arguments[ item ]= javaCast( "null", 0 );
			} else if ( findNoCase( "{#item#}", out.requestUrl ) ) {
				out.requestUrl= replaceNoCase( out.requestUrl, "{#item#}", out.args[ item ], "all" );
				structDelete( out.args, item );
			}
		}
		if ( out.verb == "GET" ) {
			out.requestUrl &= this.structToQueryString( out.args, true );
		} else if ( !structIsEmpty( out.args ) ) {
			out.body= serializeJSON( out.args );
		}
		out.requestUrl= this.apiUrl & out.requestUrl;
		this.debugLog( "API: #uCase( out.verb )#: #out.requestUrl#" );
		if ( structKeyExists( out, "body" ) ) {
			this.debugLog( out.body );
		}
		// this.debugLog( out );
		// throttle requests by sleeping the thread to prevent overloading api
		if ( this.lastRequest > 0 && this.throttle > 0 ) {
			var wait= this.throttle - ( getTickCount() - this.lastRequest );
			if ( wait > 0 ) {
				this.debugLog( "Pausing for #wait#/ms" );
				sleep( wait );
			}
		}
		cftimer( type="debug", label="omdb request" ) {
			cfhttp( result="http", method=out.verb, url=out.requestUrl, charset="UTF-8", throwOnError=false, timeOut=this.httpTimeOut ) {
				if ( out.verb == "POST" || out.verb == "PUT" || out.verb == "PATCH" ) {
					cfhttpparam( name="content-type", type="header", value="application/json" );
				}
				if ( structKeyExists( out, "body" ) ) {
					cfhttpparam( type="body", value=out.body );
				}
			}
			if ( this.throttle > 0 ) {
				this.lastRequest= getTickCount();
				server.omdb_lastRequest= this.lastRequest;
			}
		}
		out.response= toString( http.fileContent );

		// this.debugLog( http );
		// this.debugLog( out.response );
		out.statusCode= http.responseHeader.Status_Code ?: 500;
		this.debugLog( out.statusCode );
		if ( left( out.statusCode, 1 ) == 4 || left( out.statusCode, 1 ) == 5 ) {
			out.error= "status code error: #out.statusCode#";
		} else if ( out.response == "Connection Timeout" || out.response == "Connection Failure" ) {
			out.error= out.response;
		} else if ( left( out.statusCode, 1 ) == 2 ) {
			out.success= true;
		}
		// parse response 
		if ( out.success ) {
			try {
				out.data= deserializeJSON( out.response );
				if ( isStruct( out.data ) && structKeyExists( out.data, "error" ) ) {
					out.success= false;
					out.error= out.data.error;
				} else if ( isStruct( out.data ) && structKeyExists( out.data, "status" ) && out.data.status == 400 ) {
					out.success= false;
					out.error= out.data.detail;
				}
			} catch (any cfcatch) {
				out.error= "JSON Error: " & cfcatch.message & " " & cfcatch.detail;
			}
		}
		if ( len( out.error ) ) {
			out.success= false;
		}
		return out;
	}

	struct function getMovie( required string imdb_id, string type= "movie", string plot= "short" ) {
		arguments.i= this.imdbID( arguments.imdb_id );
		structDelete( arguments, "imdb_id" );
		return this.apiRequest( api= "GET /", argumentCollection= arguments );
	}

	struct function findMovie( required string title, string type= "movie", string year= "" ) {
		arguments.t= arguments.title;
		structDelete( arguments, "title" );
		arguments.y= arguments.year;
		structDelete( arguments, "year" );
		return this.apiRequest( api= "GET /", argumentCollection= arguments );
	}

	string function structToQueryString( required struct stInput, boolean bEncode= true ) {
		var sOutput= "";
		var sItem= "";
		var sValue= "";
		var amp= "?";
		for ( sItem in stInput ) {
			sValue= stInput[ sItem ];
			if ( !isNull( sValue ) && len( sValue ) ) {
				if ( bEncode ) {
					sOutput &= amp & sItem & "=" & urlEncodedFormat( sValue );
				} else {
					sOutput &= amp & sItem & "=" & sValue;
				}
				amp= "&";
			}
		}
		return sOutput;
	}

	string function imdbID( numeric input= true ) {
		if ( isNumeric( arguments.input ) ) {
			if( arguments.input >= 10000000 ) {
				arguments.input= "tt" & numberFormat( arguments.input, "00000000" );
			} else {
				arguments.input= "tt" & numberFormat( arguments.input, "0000000" );
			}
		}
		return arguments.input;
	}

}
