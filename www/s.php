<?php require_once( $_SERVER['PHP_ROOT'] . 'init.php' );

/*
 * The search results page. Only accessed indirectly, i.e. when referred to
 * within the website by a link generated by this PHP controller.
 *
 * TODO: Handle the error-situation when a user accesses this link with a valid
 * GET query set.
 */

function fetch_all( $resource ) {
	$results = array();

	while ( $r = mysql_fetch_assoc( $resource ) ) {
		$row = array();

		foreach ( $r as $k )
			array_push( $row, $k );

		array_push( $results, $row );
	}

	return $results;
}

function get_results_page_url( $num ) {
	$base_url = 'http://';
	$base_url .= $_SERVER['SERVER_NAME'] . $_SERVER['DOCUMENT_PREFIX'];
	$base_url .= '/s?';
	$base_url .= GetVariables::Query . '=';
	$base_url .= urlencode( pip_get( GetVariables::Query ) );

	$url = $base_url;

	if ( $num > 1 )
		$url .= '&start=' . ( $num - 1 ) * Pip_Search::ResultsPerPage;

	return $url;
}

function get_results_page( $num ) {
	return array(
		"num" => $num,
		"href" => get_results_page_url( $num )
		);
}

function get_found_rows() {
	$resource = pip_db_query( "SELECT FOUND_ROWS() AS `count`" );
	$array = mysql_fetch_assoc( $resource );
	return $array['count'];
}

function get_query_string( $starting_at = 0 ) {
	/* The query */
	$query = new Pip_Query();

	/* The base query string */
	$q = "SELECT SQL_CALC_FOUND_ROWS
              record_id, name, source, organ, pi
              FROM records WHERE";

	/* Find proteins which matches exact phrase */
	$q .= (" (name LIKE '%" . $query->get_exactphrase() . "%'" .
	       " OR alt_name LIKE '%" . $query->get_exactphrase() . "%')");

	/* Find proteins with names that contain these keywords */
	foreach ( $query->get_query_words_all() as $keyword )
		$q .= (" AND (name LIKE '%" . $keyword . "%'" .
		       " OR alt_name LIKE '%" . $keyword . "%')");

	/* Select proteins from a range of keywords */
	if ( 0 < count( $query->get_query_words_any() ) ) {
		$q .= " AND (";

		foreach ( $query->get_query_words_any() as $keyword )
			$q .= ("(name LIKE '%" . $keyword . "%'" .
			       " OR alt_name LIKE '%" . $keyword . "%') OR ");

		// Strip the last " OR " statement
		$q = preg_replace( '/ OR $/', '', $q );
		$q .= ")";
	}

	/* Exclude keywords from query */
	foreach ( $query->get_excluded_words() as $keyword ) {
		$q .= (" AND (name NOT LIKE '%" . $keyword . "%'" .
		       " AND alt_name NOT LIKE '%" . $keyword . "%')");
	}

	/* Select proteins from specific sources */
	if ( '' !== $query->get_source() )
		$q .= " AND (source LIKE '%" . $query->get_source() . "%')";

	/* Select proteins from specific locations/organs */
	if ( '' !== $query->get_source() )
		$q .= " AND (organ LIKE '%" . $query->get_location() . "%')";

	/* Select proteins by experimental method used */
	if ( '' !== $query->get_experimental_method() ) {
		$q .= (" AND (method LIKE '%" .
		       $query->get_experimental_method() . "%')");
	}

	/* Limit the number of results */
	$q .= " LIMIT " . $starting_at . "," . Pip_Search::ResultsPerPage;

	return $q;
}

$start_time = microtime( true );

$starting_at = pip_get_isset( GetVariables::StartAt ) ? pip_get( GetVariables::StartAt ) : 0;
$ending_at = $starting_at + Pip_Search::ResultsPerPage;

/* Perform the query */
$resource = pip_db_query( get_query_string( $starting_at ) );

if ( !$resource )
	throw new Exception( 'Failed to query database!' );

$results_count = get_found_rows();

$results = fetch_all( $resource );

/* Calculate page numbers and whatnot */
$num_of_pages = ceil( $results_count / Pip_Search::ResultsPerPage );
$current_page = $starting_at / Pip_Search::ResultsPerPage + 1;

/* Generate pagination hrefs */
$pages = array();
$starting_page = max( 1, $current_page - Pip_Search::MaxPaginationLinks / 2 );

$ending_page = min( $num_of_pages + 1,
		    $starting_page + Pip_Search::MaxPaginationLinks);

for ( $i = $starting_page; $i < $ending_page; $i++ ) {
	$url = get_results_page_url( $i );

	array_push( $pages, array( "num" => $i, "href" => $url ) );
}

$end_time = microtime( true );

$elapsed_time = $end_time - $start_time;

$content = array(
	/*
	 * The search text.
	 */
	"search_text" => pip_get( GetVariables::Query ),
	/*
	 * The elapsed time for the query (in seconds).
	 */
	"elapsed_time" => $elapsed_time,
	/*
	 * (optional)
	 * Href to download the results.
	 */
	"download" => "http://127.0.0.1",
	/*
	 * An array of results. This can be empty if no results were found.
	 */
	"results" => $results,
	/*
	 * The number of results returned.
	 */
	"results_count" => $results_count,
	/*
	 * (optional)
	 * Href to pagination links, if we returned more than one page.
	 */
	"pages" => $pages,
	/*
	 * (optional)
	 * If the results span multiple pages, set this to the page number
	 * currently being displayed.
	 */
	"current_page" => get_results_page( $current_page ),
	"first_page" => get_results_page( 1 ),
	"last_page" => get_results_page( $num_of_pages )
	);

$template = new Pip_Template( 'search' );
$template->render( $content );
