<?php

function pip_password_get_hash( $password ) {
	return pip_crypt( $password );
}

function pip_password_match( $password, $hash ) {
	return $hash == crypt( $password, $hash );
}
