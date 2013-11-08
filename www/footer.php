<?php

function get_footer() {

	echo <<<EOF
    <!-- Fixed footer -->
    <div class="navbar navbar-default navbar-bottom">

        <div class="navbar-header">

          <!-- Collapse button -->
          <button type="button" class="navbar-toggle" data-toggle="collapse" data-target=".navbar-collapse">
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
            <span class="icon-bar"></span>
          </button>

        </div> <!-- /.navbar-header -->

        <div class="navbar-collapse collapse">

          <!-- Left side -->
          <ul class="nav navbar-nav">
            <li><a href="#">About</a></li>
            <li><a href="#">Contact</a></li>
          </ul> <!-- /.navbar-nav -->

          <!-- Right side -->
          <ul class="nav navbar-nav navbar-right">
            <li><a href="#">Terms</a></li>
            <li><a href="#">Privacy</a></li>
          </ul> <!-- /.navbar-right -->

        </div><!--/.nav-collapse -->
    </div> <!-- /.navbar-fixed-bottom -->
EOF;

}