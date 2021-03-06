#!/usr/bin/env node

/*
 * yaps.js - (Yet Another Protein Schema) CSV to YAPS conversion.
 *
 * Copyright 2014 Chris Cummins.
 *
 * This file is part of pip-db.
 *
 * pip-db is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * pip-db is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with pip-db.  If not, see <http://www.gnu.org/licenses/>.
 */
var VERSION = 4;

var lazy = require('lazy');
var fs  = require('fs');
var os = require("os");
var spawn = require('child_process').spawn;

// Print a message
var message = function (msg) {
  process.stderr.write('At line ' + lineCount + ':\t' + msg + '\n');
};

// Print a warning message
var warning = function (msg) {
  message('[WARNING]\t' + msg);
};

// Print an error message
var error = function (msg) {
  message('[ERROR!!]\t' + msg);
};

// The dataset schema
var schema = [
  {name: 'Protein-Names',      regex: '(?:protein(?: name[s]?)?)|(?:alternative name ?(?:[(]?s[)]?)?)'},
  {name: 'EC',                 regex: 'e[.]?c[.]?'},
  {name: 'Source',             regex: 'source(?: ?[(]?s[)]?)?'},
  {name: 'Location',           regex: '(?:organ (?:and/or )?subcellular )?location(?: ?[(]?s[)]?)?'},
  {name: 'MW',                 regex: 'm[.]?w[.]?'},
  {name: 'Subunit-No',         regex: 'sub(?:unit)? no[.]?'},
  {name: 'Subunit-MW',         regex: 'sub(?:unit)? m[.]?w[.]?'},
  {name: 'No-Of-Iso-Enzymes',  regex: '(?:no[.]? (?:of )?)?iso[-]?enzymes'},
  {name: 'pI-Exact',           regex: 'pi'},
  {name: 'pI-Min',             regex: 'pi min(?:imum:)?(?: value)?'},
  {name: 'pI-Max',             regex: 'pi max(?:imum)?(?: value)?'},
  {name: 'pI-Major-Component', regex: 'pi (?:value of)? major component'},
  {name: 'Temperature',        regex: 'temperature(?: [(]?[ºo]?C[)]?)?'},
  {name: 'Method',             regex: '(?:experimental )?method'},
  {name: 'Full-Text',          regex: 'full text'},
  {name: 'Abstract-Only',      regex: '.*abstract(?: available)?'},
  {name: 'PubMed',             regex: 'pubmed(?: link)?'},
  {name: 'Species-Taxonomy',   regex: '(?:species )?taxonomy'},
  {name: 'Protein-Sequence',   regex: '.*sequence'},
  {name: 'Notes',              regex: 'notes'}
];

// The dataset delimiter
var delim = '\t';

var nullValueRe = new RegExp([
  '^(',
  '|(not given( \\(N[.]?G[.]?\\))?)',
  '|(n[.]?g[.]?)',
  '|(not available( \\(N[./]?A[.]?\\))?)',
  '|(no entry)',
  '|(n[./]?a[.]?)',
  '|(not applicable)',
  '|(unavailable)',
  ')$'
].join(''), 'i');

// Determines and sets the indexes of schema values
var setSchemaIndexes = function (tokens) {

  var schemaIndex, getSchemaIndex = function (value) {
    for (var j in schema) {
      var re = new RegExp('^\\s*' + schema[j].regex + '\\s*$', 'i');

      if (value.match(re)) {
        return j;
      }
    }
  };

  // Instantiate the indexes array for each property in schema
  for (var i in schema)
    schema[i].indexes = [];

  // Iterate over each column in row
  for (var i in tokens) {
    schemaIndex = getSchemaIndex(tokens[i]);

    // Add the column index to schema indexes
    if (schemaIndex)
      schema[schemaIndex].indexes.push(Number(i));
    else
      warning('Ignoring unrecognised column "' + tokens[i] + '"');
  }

  // Warn about any schema property we have left uninitialised
  for (var i in schema) {
    if (!schema[i].indexes.length)
      warning('No data column found for property "' + schema[i].name + '"');
  }
};

// Formalise a set of tokens
var tokens2Row = function (tokens) {

  var row = {};

  for (var i in schema) {

    // Compute the values from the row
    var values = (function () {
      var values = [];
      var schemaProp = schema[i];
      var prop = yaps[schemaProp.name];
      var str;

      for (var j in schemaProp.indexes) {
        str = tokens[schemaProp.indexes[j]];

        if (str !== undefined)
          str = str.trim().replace(/^"([^"]+)"$/, "$1");
        else {
          error('Line is too short. No column for property "' +
                schemaProp.name + '". Results may be corrupted.');
        }

        if (str) { // Process value
          if (str.match(nullValueRe)) // Warn if we're ignoring the value
            warning('Ignoring value "' + str + '" for property "' +
                    schemaProp.name + '"');
          else
            values.push(str);
        }
      }

      return values.length ? values : undefined;
    })();

    if (values)
      row[schema[i].name] = values;
  }

  return row;
};

// Capitalise the first letter of a string, IF and ONLY IF the first
// letter is a standard ASCII letter. We don't capitalise Greek
// letters.
var capitalise = function (txt) {
  return /^[\000-\177]*$/.test(txt) ?
        txt.charAt(0).toUpperCase() + txt.substr(1) : txt;
}

// Convert a row object into a Yaps object
var row2Yaps = function (row) {

  var yaps = {};

  // Protein names
  if (row['Protein-Names']) {
    yaps['Protein-Names'] = (function (arr) {
      var n = [];

      for (var i in arr)
        n.push.apply(n, arr[i].split('/'));

      for (var i in n) // Format individual names
        n[i] = capitalise(n[i].trim()).replace(/\.$/, ''); // Strip trailing '.'

      return n;
    })(row['Protein-Names']);
  }

  // Enzyme commission number
  if (row['EC'])
    yaps['EC'] = row['EC'][0];

  // Source
  if (row['Source'])
    yaps['Source'] = capitalise(row['Source'][0]);

  // Location
  if (row['Location'])
    yaps['Location'] = capitalise(row['Location'][0]);

  // MW
  if (row['MW']) {
    var c = row['MW'][0].split(/ ?[-\/] ?/);

    yaps['MW-Min'] = c[0];
    yaps['MW-Max'] = c.length > 1 ? c[1] : c[0];
  }

  // Subunit No.
  if (row['Subunit-No'])
    yaps['Subunit-No'] = row['Subunit-No'][0];

  // Subunit M.W
  if (row['Subunit-MW'])
    yaps['Subunit-MW'] = row['Subunit-MW'][0];

  // No of Iso-Enzymes
  if (row['No-Of-Iso-Enzymes'])
    yaps['No-Of-Iso-Enzymes'] = row['No-Of-Iso-Enzymes'][0];

  // pI min & pI Max
  if (row['pI-Exact']) {
    yaps['pI-Min'] = row['pI-Exact'][0];
    yaps['pI-Max'] = row['pI-Exact'][0];
  } else {

    if (row['pI-Min'])
      yaps['pI-Min'] = row['pI-Min'][0];

    if (row['pI-Max'])
      yaps['pI-Max'] = row['pI-Max'][0];
  }

  // pI major
  if (row['pI-Major-Component'])
    yaps['pI-Major-Component'] = row['pI-Major-Component'][0];

  // Temperature
  if (row['Temperature']) {
    var c = row['Temperature'][0].replace(/[ºْ]/, '').split(/ ?[-\/] ?/);

    yaps['Temperature-Min'] = c[0];
    yaps['Temperature-Max'] = c.length > 1 ? c[1] : c[0];
  }

  // Experimental method
  if (row['Method'])
    yaps['Method'] = row['Method'][0];

  // References
  if (row['Full-Text'])
    yaps['Full-Text'] = row['Full-Text'][0];

  if (row['Abstract-Only'])
    yaps['Abstract-Only'] = row['Abstract-Only'][0];

  if (row['PubMed'])
    yaps['PubMed'] = row['PubMed'][0];

  if (row['Species-Taxonomy'])
    yaps['Species-Taxonomy'] = row['Species-Taxonomy'][0];

  if (row['Protein-Sequence'])
    yaps['Protein-Sequence'] = row['Protein-Sequence'][0];

  // Notes
  if (row['Notes'])
    yaps['Notes'] = row['Notes'][0];

  return yaps;
};

// Invoke fetch-fasta on the supplied sequences and assign them to the
// yaps object.
var setFastaSequences = function() {
  var ff = spawn('fetch-fasta'), out = '';

  // Write in the sequence URLs
  ff.stdin.write((function () {
    var s = [], r;

    for (var i in yaps['Records']) {
      r = yaps['Records'][i], url = r['Protein-Sequence'];

      if (url)
        s.push(url);
    }

    return s.join('\n');
  })());
  ff.stdin.end();

  ff.stdout.on('data', function (data) {
    out += data.toString();
  });

  ff.stderr.on('data', function (data) {
    process.stderr.write(data.toString());
  });

  ff.on('close', function (code) {
    var records = out.split('\n'), data = [], r, seq, url, fasta;

    if (code)
      error('fetch-fasta failed with exit code ' + code);

    // Assemble list of sequences
    for (var i in records)
      if (records[i])
        data.push(JSON.parse(records[i]));

    // Iterate over every record
    for (var i in yaps['Records']) {
      r = yaps['Records'][i];

      for (var j in data) {
        seq = data[j];

        // Match URL with sequence
        if (r['Protein-Sequence'] === seq['url']) {
          r['Sequence-Name'] = seq['name'];
          r['Sequence-Data'] = seq['data'];
          break;
        }
      }
    };

    // Pretty-print JSON
    console.log(JSON.stringify(yaps, undefined, 2));
  });
}

// Process arguments
var argv = process.argv, argc = argv.length;

if (argc !== 3) {
  console.log('Usage <csv-file>');
  process.exit(1);
}

// Global state objects
var csv = fs.realpathSync(argv[2]);
var lineCount = 1;
var readStream = fs.createReadStream(csv);
var yaps = {
  "Encoding": "yaps",
  "Version": VERSION,
  "Date": new Date().toISOString().slice(0, 19).replace('T', ' '),
  "Author": process.env['USER'] + "@" + os.hostname(),
  "Agent": __filename,
  "Source": csv,
  "No-Of-Records": 0,
  "Records": []
};

readStream.on('error', function (error) {
  process.stderr.write('Unable to read file "' + csv + '"!\n');
});

new lazy(readStream).on('end', function () {
  // End of processing callback
  yaps['No-Of-Records'] = yaps['Records'].length;
  setFastaSequences(); // Crawl the FASTA sequences
}).lines.forEach(function (buffer) {
  // Per-line callback
  var line = buffer.toString().replace(/\r/, ''); // Strip carriage return
  var tokens = line.split(delim);

  if (schema[0].indexes) // Body
    yaps['Records'].push(row2Yaps(tokens2Row(tokens)));
  else // Header line
    setSchemaIndexes(tokens);

  lineCount++;
});
