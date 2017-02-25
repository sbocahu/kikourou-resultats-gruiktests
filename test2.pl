#!/usr/bin/env perl
use strict;
use warnings;

use Mojolicious::Lite;
use IPC::Run qw(run timeout);
use File::Slurp;
use Cwd;
use JSON;

app->static->paths->[0] = getcwd;


sub pdf2csv {
  my $pdf = shift;
  my $cols_col = shift;
  my $nbf = shift;
  my $fixed = shift;

  my $ret = "class;temps;nom;cat;sexe;club\n";
  my @cmd;

  if($fixed > 0) {
    @cmd = (qw(pdftotext -fixed), $fixed, qw(-layout - -));
  } else {
    @cmd = qw(pdftotext -layout - -);
  }

  my ($out, $err);

  run \@cmd, \$pdf, \$out, \$err, timeout(10) or die "pdftotext execution failed: $?";

  foreach my $line (split /\n+/, $out) {
    #my ($class_col, $temps_col, $nom_col, $cat_col, $sexe_col, $club_col) = (0, 4, 2, 7, -1, 3);
    #my ($class_col, $temps_col, $nom_col, $cat_col, $sexe_col, $club_col) = (0, 3, 1, 5, 6, 7);
    my ($class_col, $temps_col, $nom_col, $prenom_col, $cat_col, $sexe_col, $club_col) = @$cols_col;
  
    next if not $line =~ /[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/;
    $line =~ s/^\s+//;
  
  
    my @fields = split /\s\s+/, $line;
  #   use Data::Dumper;
  #  print Dumper(@fields), "\n";
  #  exit;
  
    my $club = '';
  
    # workaround for cases where the TEAM column is empty, (resulting in less fields when the line is split)
    # less field = no team/club, and we need to shift other cols
    #FIXME doesn't work with 2 or more potentially empty fields (unless at EOL). eg: club and license numbers
    if(scalar(@fields) < $nbf and $club_col < $nbf) {
      $class_col-- if $class_col > $club_col;
      $temps_col-- if $temps_col > $club_col;
      $nom_col-- if $nom_col > $club_col;
      $prenom_col-- if $prenom_col > $club_col;
      $cat_col-- if $cat_col > $club_col;
      $sexe_col-- if $sexe_col > $club_col;
    } elsif(scalar(@fields) < $nbf and $club_col == $nbf) {
      $club = $fields[$club_col-1]; chomp $club;
    } else {
      $club = $fields[$club_col]; chomp $club;
    }
  
    my $class = $fields[$class_col]; $class =~ s/ //g;
    next if $class =~ /(ABD|DNF|DNS)/;
    my $temps = $fields[$temps_col]; chomp $temps;
    my $nom = $fields[$nom_col]; chomp $nom;
    if($prenom_col gt 0) {
      my $prenom = $fields[$prenom_col]; chomp $prenom;
      $nom .= " $prenom";
    }
    my $cat = $fields[$cat_col];
      chomp $cat;
      $cat =~ s/M([0-5])/V$1/;
      $cat =~ s/^[0-9]+\.? //;
    my $sexe;
    if($sexe_col eq -1) {
      $sexe = ($cat =~ /F/) ? 'F' : 'M'; 
    } else {
      $sexe = $fields[$sexe_col]; chomp $sexe;
    }
  
    $ret .= join(';', $class, $temps, $nom, $cat, $sexe, $club); $ret .= "\n";
  }

  return $ret;
};


#S0
sub pdf2json {
  my $pdf = shift;
  my $fixed = shift || 0;

  my @cmd;

  if($fixed > 0) {
    @cmd = (qw(pdftotext -fixed), $fixed, qw(-layout - -));
  } else {
    @cmd = qw(pdftotext -layout - -);
  }

  my ($out, $err);

  run \@cmd, \$pdf, \$out, \$err, timeout(10) or die "pdftotext execution failed: $?";

  my @ret;
  foreach my $line (split /\n+/, $out) {
    next if not $line =~ /[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/;
    $line =~ s/^\s+//;
    next if $line =~ /(ABD|DNF|DNS)/;
    $line =~ s/\f//g;
    my @fields = split /\s\s+/, $line;
    push @ret, [ @fields ] if scalar(@fields) > 3;
  }
  my $json = to_json(\@ret);
  $json =~ s/'/\\'/g;
  return $json;
};




any '/' => sub {
    my $self = shift;
    $self->redirect_to('/kikou');
};



#S1
my @presets = [
  { name => "Dansoft chronometrage",
    numbers => "[1, 4, 2, 0, 6, 7, 8, 9, 0]"
  },
  { name => "Yaka chrono (ancien)",
    numbers => "[1, 5, 3, 0, 8, 0, 4, 9, 0]",
  },
  { name => "Yaka chrono (2017)",
    numbers => "[1, 6, 3, 4, 8, 0, 5, 10, 0]",
  },
  { name => "Sport Info",
    numbers => "[1, 3, 4, 0, 9, 7, 5, 11, 0]",
  },
  { name => "L-Chrono",
    numbers => "[1, 7, 2, 0, 5, 0, 10, 10, 4]",
  }
];

any '/kikouchrono' => sub {
    my $self = shift;
    $self->stash(
      presets => @presets
    );

    # Check file size
    return $self->render(text => 'File is too big.', status => 200)
        if $self->req->is_limit_exceeded;

    # Process uploaded file
    if (my $example = $self->req->upload('example')) {

        my $cols = [
          ($self->param('class_col')-1),
          ($self->param('temps_col')-1),
          ($self->param('nom_col')-1),
          ($self->param('prenom_col')-1),
          ($self->param('cat_col')-1),
          ($self->param('sexe_col')-1),
          ($self->param('club_col')-1)
        ];
        my $nbf = $self->param('nbf');
        my $fixed = $self->param('fixed');
	my $content = pdf2csv($example->slurp, $cols, $nbf, $fixed);
        my $name = $example->filename;
        write_file("tmp/$name.csv", $content);
	$self->stash(
          name => $example->filename,
        );
        $self->render(template => "result");
    }
};

#S2
any '/kik' => sub {
    my $self = shift;

    # Check file size
    return $self->render(text => 'File is too big.', status => 200)
        if $self->req->is_limit_exceeded;

    # Process uploaded file
    if (my $example = $self->req->upload('example')) {
	my $content = pdf2json($example->slurp);
	$self->stash(
          csv_data => $content,
        );
        $self->render(template => "kikmycsv");
    }
};




#S3
any '/kikou' => sub {
    my $self = shift;
    $self->stash(
      presets => [
        { name => "Dansoft chronometrage",
          numbers => "[1, 4, 2, 0, 6, 7, 8, 9, 0]"
        },
        { name => "Yaka chrono (ancien)",
          numbers => "[1, 5, 3, 0, 8, 0, 4, 9, 0]",
        },
        { name => "Yaka chrono (2017)",
          numbers => "[1, 6, 3, 4, 8, 0, 5, 10, 0]",
        },
        { name => "Sport Info",
          numbers => "[1, 3, 4, 0, 9, 7, 5, 11, 0]",
        },
        { name => "L-Chrono",
          numbers => "[1, 7, 2, 0, 5, 0, 10, 10, 4]",
        }
      ]
    );

    # Check file size
    return $self->render(text => 'File is too big.', status => 200)
        if $self->req->is_limit_exceeded;

    # Process uploaded file
    if (my $example = $self->req->upload('example')) {

        #my $cols = [0, 3, 1, 5, 6, 7];
        my $cols = [
          ($self->param('class_col')-1),
          ($self->param('temps_col')-1),
          ($self->param('nom_col')-1),
          ($self->param('prenom_col')-1),
          ($self->param('cat_col')-1),
          ($self->param('sexe_col')-1),
          ($self->param('club_col')-1)
        ];
        my $nbf = $self->param('nbf');
        my $fixed = $self->param('fixed');
	my $content = pdf2csv($example->slurp, $cols, $nbf, $fixed);
        my $name = $example->filename;
        write_file("tmp/$name.csv", $content);
	$self->stash(
          name => $example->filename,
        );
        $self->render(template => "result");
    }
};

app->start;

__DATA__
@@ kikou.html.ep
<!DOCTYPE html>
<html>
    <head><title>Upload</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <style>
      input { display: block; }
    </style>
    </head>
    <body>
      % my @attrs = (method => 'POST', enctype => 'multipart/form-data');
 <div class="dropdown">
  <button class="btn btn-primary dropdown-toggle" type="button" data-toggle="dropdown">Préselections d'ordre des colonnes<span class="caret"></span></button>
  <ul class="dropdown-menu">
% foreach my $preset (@$presets) {
    <li><a href="javascript:presets(<%= $preset->{numbers} %>)"><%= $preset->{name} %></a></li>
% }
  </ul>
</div> 
      %= form_for kikou => @attrs => begin
        %= label_for example => 'Choisissez un fichier PDF'
        %= file_field 'example'

        %= label_for class_col => 'Colonne correspondante au classement'
        %= number_field class_col => 1, id => 'class_col', min => 1, max => 20
        %= label_for temps_col => 'Colonne correspondante au temps'
        %= number_field temps_col => 2, id => 'temps_col', min => 1, max => 20
        %= label_for nom_col => 'Colonne correspondante à l\'identité'
        %= number_field nom_col => 3, id => 'nom_col', min => 1, max => 20
        %= label_for prenom_col => 'Colonne correspondante au prenom (0 si contenu dans le champs nom)'
        %= number_field prenom_col => 4, id => 'prenom_col', min => 0, max => 20
        %= label_for cat_col => 'Colonne correspondante à la catégorie'
        %= number_field cat_col => 5, id => 'cat_col', min => 1, max => 20
        %= label_for sexe_col => 'Colonne correspondante au sexe (0 pour autodétection via le champs catégorie)'
        %= number_field sexe_col => 0, id => 'sexe_col', min => 0, max => 20
        %= label_for club_col => 'Colonne correspondante au club / team'
        %= number_field club_col => 6, id => 'club_col', min => 1, max => 20
        %= label_for nbf => 'Nombre de colonnes (sert pour contourner le cas de champs club vide)'
        %= number_field nbf => 9, id => 'nbf', min => 5, max => 20
        %= label_for fixed => 'Fixed-pitch character width. 0: non-fixed, 4 peut parfois être efficace'
        %= number_field fixed => 0, id => 'fixed', min => 0, max => 8
        %= submit_button 'Envoyer'
      % end
    <script type="text/javascript" src="js/jquery.min.js"></script>
    <script type="text/javascript" src="js/bootstrap.min.js"></script>
<script type="text/javascript">
function presets(conf){
  $('#class_col').val(conf[0]);
  $('#temps_col').val(conf[1]);
  $('#nom_col').val(conf[2]);
  $('#prenom_col').val(conf[3]);
  $('#cat_col').val(conf[4]);
  $('#sexe_col').val(conf[5]);
  $('#club_col').val(conf[6]);
  $('#nbf').val(conf[7]);
  $('#fixed').val(conf[8]);
}
</script>
    </body>
</html>

@@ result.html.ep
<!DOCTYPE html>
<html>
    <head><title>result</title>
    <!-- Bootstrap core CSS -->
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <link href="css/dataTables.bootstrap.css" rel="stylesheet">

    <!-- HTML5 shim and Respond.js for IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script type="text/javascript" src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
      <script type="text/javascript" src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
    <![endif]-->

    </head>
    <body>
    <div class="container-fluid">

      <div id='table-container'></div>

    </div>

    <!-- Bootstrap core JavaScript
    ================================================== -->
    <!-- Placed at the end of the document so the pages load faster -->
    <script type="text/javascript" src="js/jquery.min.js"></script>
    <script type="text/javascript" src="js/bootstrap.min.js"></script>
    <script type="text/javascript" src="js/jquery.csv.min.js"></script>
    <script type="text/javascript" src="js/jquery.dataTables.min.js"></script>
    <script type="text/javascript" src="js/dataTables.bootstrap.js"></script>
    <script type="text/javascript" src="js/csv_to_html_table.js"></script>


    <script type="text/javascript">
      function format_link(link){
        if (link)
          return "<a href='" + link + "' target='_blank'>" + link + "</a>";
        else
          return "";
      }

      CsvToHtmlTable.init({
        csv_path: 'tmp/<%= $name %>.csv',
        element: 'table-container',
        allow_download: true,
        csv_options: {separator: ';', delimiter: '"'},
        datatables_options: {"paging": false},
        custom_formatting: [[4, format_link]]
      });
    </script>

    </body>
</html>

@@ kikmycsv.html.ep
<!DOCTYPE html>
<html>
    <head><title>result</title>
    <!-- Bootstrap core CSS -->
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <link href="css/dataTables.bootstrap.css" rel="stylesheet">

    <!-- HTML5 shim and Respond.js for IE8 support of HTML5 elements and media queries -->
    <!--[if lt IE 9]>
      <script type="text/javascript" src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
      <script type="text/javascript" src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
    <![endif]-->

    </head>
    <body>
    <!-- Bootstrap core JavaScript
    ================================================== -->
    <!-- Placed at the end of the document so the pages load faster -->
    <script type="text/javascript" src="js/jquery.min.js"></script>
    <script type="text/javascript" src="js/bootstrap.min.js"></script>
    <script type="text/javascript" src="js/jquery.csv.min.js"></script>
    <script type="text/javascript" src="js/jquery.dataTables.min.js"></script>
    <script type="text/javascript" src="js/dataTables.bootstrap.js"></script>
    <script type="text/javascript" src="js/csv_to_html_table2.js"></script>


    <script type="text/javascript">

var presets = jQuery.parseJSON(`
  [ 
    { "name": "Dansoft chronometrage",
      "numbers": [1, 4, 2, 0, 6, 7, 8, 9, 0]
    },
    { "name": "Yaka chrono (ancien)",
      "numbers": [1, 5, 3, 0, 8, 0, 4, 9, 0]
    },
    { "name": "Yaka chrono (2017)",
      "numbers": [1, 6, 3, 4, 8, 0, 5, 10, 0]
    },
    { "name": "Sport Info",
      "numbers": [1, 3, 4, 0, 9, 7, 5, 11, 0]
    },
    { "name": "L-Chrono",
      "numbers": [1, 7, 2, 0, 5, 0, 10, 10, 4]
    }
  ]
`);

function update_table() {
      CsvToHtmlTable.init({
        csv_data: $("#csv").val(),
        element: 'table-container',
        allow_download: false,
        csv_options: {separator: ';', delimiter: '"'},
        datatables_options: {"paging": false},
      });
};


function json2csv() {
var csv_data = "class;temps;nom;cat;sexe;club\n";

$.each(data, function(i, l) {

var class_col = $("#class_col").val() - 1;
var club_col = $("#club_col").val() - 1;
var sexe_col = $("#sexe_col").val() - 1;
var temps_col = $("#temps_col").val() - 1;
var nom_col = $("#nom_col").val() - 1;
var prenom_col = $("#prenom_col").val() - 1;
var cat_col = $("#cat_col").val() - 1;
var nbf = $("#nbf").val();


  var club = "";

  if(l.length < nbf && club_col < nbf) {
    if(class_col > club_col) { class_col--; } 
    if(sexe_col > club_col) { sexe_col--; } 
    if(nom_col > club_col) { nom_col--; } 
    if(prenom_col > club_col) { prenom_col--; } 
    if(temps_col > club_col) { temps_col--; } 
    if(cat_col > club_col) { cat_col--; } 
  } else if(l.length < nbf && club_col == nbf) {
    club = l[(club_col-1)];
  } else {
    club = l[club_col];
  }

  var clas = l[class_col];
  if(/(ABD|DNS|DNF)/.test(clas)) { return true; } // continue
 
  var temps = l[temps_col];
  var nom = l[nom_col];
  if(prenom_col > -1) {
    var prenom = l[prenom_col];
    nom += " "+prenom;
  }
  var cat = l[cat_col];
    cat = cat.replace(/M([0-5])/, "V$1");
    cat = cat.replace(/^[0-9]+\.? /, "");
  var sexe;
  if(sexe_col == -1) {
    sexe = (/F/.test(cat)) ? 'F' : 'M';
  } else {
    sexe = l[sexe_col];
  }

  csv_data += clas+";"+temps+";"+nom+";"+cat+";"+sexe+";"+club+"\n";
});

$("#csv").val(csv_data);
update_table();
};

function setpresets(i){
  var conf = presets[i]['numbers'];
  $('#class_col').val(conf[0]);
  $('#temps_col').val(conf[1]);
  $('#nom_col').val(conf[2]);
  $('#prenom_col').val(conf[3]);
  $('#cat_col').val(conf[4]);
  $('#sexe_col').val(conf[5]);
  $('#club_col').val(conf[6]);
  $('#nbf').val(conf[7]);
//  $('#fixed').val(conf[8]);
}

    </script>

 <div class="dropdown" id="dp">
  <button class="btn btn-primary dropdown-toggle" type="button" data-toggle="dropdown">Préselections d'ordre des colonnes<span class="caret"></span></button>
  <ul class="dropdown-menu">
  </ul>
</div> 

<div id="container-controls" style="display: -webkit-flex;display: -ms-flexbox;display: flex;">

      <form action="" method="GET">
 <div class="form-group">
        <label for="class_col" class="form-control">Colonne correspondante au classement</label>
        <input onchange="javascript:json2csv()" class="form-control" id="class_col" max="20" min="1" name="class_col" type="number" value="1" />
        <label for="temps_col">Colonne correspondante au temps</label>
        <input onchange="javascript:json2csv()" class="form-control" id="temps_col" max="20" min="1" name="temps_col" type="number" value="2" />
        <label for="nom_col">Colonne correspondante à l&#39;identité</label>
        <input onchange="javascript:json2csv()" class="form-control" id="nom_col" max="20" min="1" name="nom_col" type="number" value="3" />
        <label for="prenom_col">Colonne correspondante au prenom (0 si contenu dans le champs nom)</label>
        <input onchange="javascript:json2csv()" class="form-control" id="prenom_col" max="20" min="0" name="prenom_col" type="number" value="4" />
        <label for="cat_col">Colonne correspondante à la catégorie</label>
        <input onchange="javascript:json2csv()" class="form-control" id="cat_col" max="20" min="1" name="cat_col" type="number" value="5" />
        <label for="sexe_col">Colonne correspondante au sexe (0 pour autodétection via le champs catégorie)</label>
        <input onchange="javascript:json2csv()" class="form-control" id="sexe_col" max="20" min="0" name="sexe_col" type="number" value="0" />
        <label for="club_col">Colonne correspondante au club / team</label>
        <input onchange="javascript:json2csv()" class="form-control" id="club_col" max="20" min="1" name="club_col" type="number" value="6" />
        <label for="nbf">Nombre de colonnes (sert pour contourner le cas de champs club vide)</label>
        <input onchange="javascript:json2csv()" class="form-control" id="nbf" max="20" min="5" name="nbf" type="number" value="9" />
        <input class="form-control" type="button" value="Envoyer" onclick="javascript:json2csv()"/>
</div>
</form>

<textarea id="csv" style="width: 80%;" onchange="javascript:update_table()">
</textarea>

</div>

<h4>Prévisualisation du CSV non traité (pour récupérer des données pour édition manuelle) et du CSV traité (pour vérification)</h4>
    <div class="container-fluid">

      <div style="max-height: 160px; overflow: scroll" id='preview-container'></div>
      <div id='table-container'></div>

    </div>

    <script type="text/javascript">

$.each(presets, function(i, v) {
  $("#dp ul").append('<li><a href="javascript:setpresets('+i+')">'+v["name"]+'</a></li>');
}); 
var data = jQuery.parseJSON('<%== $csv_data %>');
var unmodified = '';
var m = 1;
$.each(data, function(i, l) {
  m = Math.max(m, l.length);
  unmodified += l.join(";")+"\n";
});
unmodified = "col;".repeat(m)+"\n"+unmodified;
      CsvToHtmlTable.init({
        csv_data: unmodified,
        element: 'preview-container',
        allow_download: false,
        csv_options: {separator: ';', delimiter: '"'},
        datatables_options: {"paging": false} 
      });

//, columnDefs: { targets: '_all', defaultContent: "N/A" }}

json2csv();

</script>

    </body>
</html>

@@ kik.html.ep
<!DOCTYPE html>
<html>
    <head><title>Upload</title>
    <link href="css/bootstrap.min.css" rel="stylesheet">
    <style>
      input { display: block; }
    </style>
    </head>
    <body>
      % my @attrs = (method => 'POST', enctype => 'multipart/form-data');
      %= form_for kik => @attrs => begin
        %= label_for example => 'Choisissez un fichier PDF'
        %= file_field 'example'
        %= submit_button 'Envoyer'
      % end
    <script type="text/javascript" src="js/jquery.min.js"></script>
    <script type="text/javascript" src="js/bootstrap.min.js"></script>
    </body>
</html>


