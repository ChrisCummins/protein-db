<?php

/*
 * Returns the contents of the _SERVER debugging superglobal.
 */
function pip_server_get_debug() {
	if ( isset( $_SERVER['DEBUG'] ) )
		return $_SERVER['DEBUG'];
	else
		return '';
}
