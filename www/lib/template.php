<?php

$template_dir = './html/';
$template_extension = '.html';

$twig_autoloader = './lib/Twig/Autoloader.php';

require_once( $twig_autoloader );

Twig_Autoloader::register();

$twig_loader = new Twig_Loader_Filesystem( $template_dir );
$twig_args = array();

$twig = new Twig_Environment( $twig_loader, $twig_args );

/*
 * Throw a custom exception for the tempalte engine.
 */
function pip_throw_template_error( $msg ) {
	throw new Exception( 'lib/template.php: ' . $msg );
}

/*
 * For a given template name, return the template source file.
 */
function pip_get_template_file( $name ) {
	global $template_extension;

	return $name . $template_extension;
}

/*
 * Returns the path to a template file in the form:
 *
 *      <dir>/<name>.<ext>
 */
function pip_get_template_path( $name ) {
	global $template_dir;

	return $template_dir . pip_get_template_file( $name );
}

/*
 * Returns whether a template has a corresponding source file.
 */
function pip_template_exists( $name ) {
	return file_exists( pip_get_template_path( $name ) );
}

/*
 * Returns true if a template is private, else false.
 */
function pip_template_is_private( $name ) {
	return '_' == $name[0];
}

/*
 * Renders a given template.
 */
function pip_render_template( $name, $content = array() ) {
	global $twig;

	if ( !pip_template_exists( $name ) )
		pip_throw_template_error( 'Template not found!' );

	if ( pip_template_is_private( $name ) )
		pip_throw_template_error( 'Private template should not be rendered' );

	$content = pip_append_session_to_array( $content );

	$template = $twig->loadTemplate( pip_get_template_file( $name ) );

	$template->display( $content );
}
