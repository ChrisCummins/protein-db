<?php


class PipDbException extends Exception {}

/*
 * Initialise a connection with the database.
 */
function pip_db_init() {

	$status = mysql_connect( PipDatabase::Host,
				 PipDatabase::Username,
				 PipDatabase::Password );

	if ( !$status )
		throw new PipDbException( 'Failed to connect to with user credentials!' );

	$status = mysql_select_db( PipDatabase::Name );

	if ( !$status )
		throw new PipDbException( 'Failed to connect to dabase!' );

}

/*
 * Query the database.
 */
function pip_db_query( $query ) {
	return mysql_query( $query );
}

/*
 * Create a new database table.
 */
function pip_db_table_create( $name, $query ) {
	return pip_db_query( "CREATE TABLE IF NOT EXISTS $name($query)" );
}
