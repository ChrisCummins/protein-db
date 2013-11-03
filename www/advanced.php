<!doctype html>
<html lang="en">

  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">

    <title>pip-db Advanced Search</title>

    <link rel="stylesheet" href="css/styles.css"/>
    <link rel="stylesheet" href="css/bootstrap.css">
  </head>

  <body>

    <!-- Search box -->
    <div class="search inline">
      <a href="index.html"><h1 class="logo">pip-db</h1></a>
    </div>

    <div class="container">

      <div class="page-title">
        <h3>Advanced Search</h3>
        <hr>
      </div> <!-- /.page-title -->

      <div class="advsearch">
        <form method="GET">

          <div class="row">
            <div class="col-md-12"><h4>Find proteins with...</h4></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="words-all">all of these words:</label>
            </div>
            <div class="col-md-6"><input id="words-all" type="text"></div>
            <div class="col-md-4"><div class="info">
                Find proteins with names that contain these keywords.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="words-exact">this exact word or phrase:</label>
            </div>
            <div class="col-md-6"><input id="words-exact" type="text"></div>
            <div class="col-md-4"><div class="info">
                Type exact phrases to match in protein names.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="words-any">any of these words:</label>
            </div>
            <div class="col-md-6"><input id="words-any" type="text"></div>
            <div class="col-md-4"><div class="info">
                Select proteins from a range of keywords.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="words-none">none of these words:</label>
            </div>
            <div class="col-md-6"><input id="words-none" type="text"></div>
            <div class="col-md-4"><div class="info">
                Exclude proteins which contain these keywords.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="source">source:</label>
            </div>
            <div class="col-md-6"><input id="source" type="text"></div>
            <div class="col-md-4"><div class="info">
                Enter the Latin binomial or common names.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="location">location:</label>
            </div>
            <div class="col-md-6"><input id="location" type="text"></div>
            <div class="col-md-4"><div class="info">
                Enter the location or organ.
            </div></div>
          </div>

          <hr>

          <div class="row">
            <div class="col-md-12"><h4>Then narrow results by...</h4></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="location">enzyme commision number:</label>
            </div>
            <div class="col-md-6">
              <div style="display: table; width:100%;">
                <div style="display: table-cell; padding-right: 16px;">
                  <input id="ec1" type="text">
                </div>
                <div style="display: table-cell; padding-right: 16px;">
                  <input id="ec2" type="text">
                </div>
                <div style="display: table-cell; padding-right: 16px;">
                  <input id="ec3" type="text">
                </div>
                <div style="display: table-cell;">
                  <input id="ec4" type="text">
                </div>
              </div>
            </div>
            <div class="col-md-4"><div class="info">
                Enter one or more categories for the EC.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="pi-min">isoelectric point:</label>
            </div>
            <div class="col-md-6">
              <div style="display: table; width:100%;">
                <div style="display: table-cell;">
                  <input id="pi-min" type="text">
                </div>
                <div style="display: table-cell;width:40px;padding-right:6px;padding-left:6px;text-align: center;">to</div>
                <div style="display: table-cell;">
                  <input id="pi-max" type="text">
                </div>
              </div>
            </div>
            <div class="col-md-4"><div class="info">
                Select from an exact or range of isoelectric points.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="location">molecular weight:</label>
            </div>
            <div class="col-md-6">
              <div style="display: table; width:100%;">
                <div style="display: table-cell;">
                  <input id="mw-min" type="text">
                </div>
                <div style="display: table-cell;width:40px;padding-right:6px;padding-left:6px;text-align: center;">to</div>
                <div style="display: table-cell;">
                  <input id="mw-max" type="text">
                </div>
              </div>
            </div>
            <div class="col-md-4"><div class="info">
                Select from an exact or range of molecular weights.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="location">experimental method:</label>
            </div>
            <div class="col-md-6">
              <select>
                <option>Analytical gel isoelectric focusing</option>
                <option>Analytical isoelectric focusing</option>
                <option>Carrier-free isoelectric focusing</option>
                <option>Column isoelectric focusing</option>
                <option>Density gradient isoelectric focusing</option>
                <option>Disc electrophoresis</option>
                <option>Disc gel electrophoresis</option>
                <option>Electrofocusing</option>
                <option>Electrophoresis</option>
                <option>Electrostatic Focusing</option>
                <option>Gel electrophoresis</option>
                <option>Gel isoelectric focusing</option>
                <option>Isoelectric density gradient electrophoresis</option>
                <option>Isoelectric focusing in polyacrylamide gel</option>
                <option>Isoelectric focusing in polyacrylamide gels</option>
                <option>Isoelectric focusing on acrylamide gel</option>
                <option>Isoelectric Focusing with a Carrier Ampholyte</option>
                <option>Isoelectric focusing</option>
                <option>Isoelectric fractionation</option>
                <option>Isoelectrofocusing</option>
                <option>LKB apparatus</option>
                <option>LKB electrofocusing apparatus</option>
                <option>Measurement with an antimony microelectrode</option>
                <option>Microisoelectric focusing on polyacrylamide gel</option>
                <option>Polyacrylamide disc electrophoresis</option>
                <option>Polyacrylamide gel electrofucusing</option>
                <option>Polyacrylamide gel isoelectric focusing</option>
                <option>Preparative isoelectric focusing</option>
                <option>SDS disc electrophoresis</option>
                <option>SDS gel electrophoresis</option>
                <option>Stationary electrolysis</option>
                <option>Thin-layer isoelectric focusing</option>
                <option>Vesterberg and Svensson method</option>
              </select>
            </div>
            <div class="col-md-4"><div class="info">
                Select the method which was used to determine the result.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2">
              <label for="location">temperature:</label>
            </div>
            <div class="col-md-6">
              <div style="display: table; width:100%;">
                <div style="display: table-cell;">
                  <input id="location" type="text">
                </div>
                <div style="display: table-cell;width:40px;padding-right:6px;padding-left:6px;text-align: center;">to</div>
                <div style="display: table-cell;">
                  <input id="location" type="text">
                </div>
              </div>
            </div>
            <div class="col-md-4"><div class="info">
                Select from an exact or range of temperatures.
            </div></div>
          </div>

          <div class="row">
            <div class="col-md-2 col-md-offset-6">
              <button id="submit" class="btn btn-info">Advanced Search</button>
            </div>
          </div>
        </form>
      </div> <!-- /.advanced-search -->

    </div>

    <script src="//code.jquery.com/jquery.js"></script>
    <script src="js/bootstrap.js"></script>
  </body>

</html>