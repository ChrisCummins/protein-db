<?php

/*
 * Returns whether the site is in debugging mode or not.
 */
function pip_debugging() {
	return 'yes' == pip_server_get_debug();
}

/*
 * Error handler.
 */
function pip_error_handler( $num, $str, $file, $line, $context = null )
{
	pip_exception_handler( new ErrorException( $str, 0, $num,
						   $file, $line ) );
}

/*
 * Exception handler.
 */
function pip_exception_handler( Exception $e ) {
	print "<div style='text-align: center;'>";
	print "<h2 style='color: rgb(190, 50, 50);'>Exception Occured:</h2>";
	print "<table style='width: 800px; display: inline-block;'>";
	print "<tr style='background-color:rgb(230,230,230);'><th style='width: 80px;'>Type</th><td>" . get_class( $e ) . "</td></tr>";
	print "<tr style='background-color:rgb(240,240,240);'><th>Message</th><td>{$e->getMessage()}</td></tr>";
	print "<tr style='background-color:rgb(230,230,230);'><th>File</th><td>{$e->getFile()}</td></tr>";
	print "<tr style='background-color:rgb(240,240,240);'><th>Line</th><td>{$e->getLine()}</td></tr>";
	print "</table></div>";
	exit();
}

/**
 * Shutdown handler.
 */
function shutdown_handler() {
	$e = error_get_last();

	if ( $e['type'] == E_ERROR ) {
		pip_error_handler( $e['type'], $e['message'],
				   $e['file'], $e['line'] );
	}
}

if ( pip_debugging() ) {

	/* Display errors */
	ini_set( 'display_errors', 'Off' );

	/* Set a high error-reporting level */
	error_reporting( E_ALL | E_STRICT );

	/* Register our custom error handlers */
	set_error_handler( 'pip_error_handler' );
	set_exception_handler( 'pip_exception_handler' );
	register_shutdown_function( 'shutdown_handler' );

}