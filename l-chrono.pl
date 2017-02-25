#!/usr/bin/env perl
use strict;
use warnings;

use Mojolicious::Lite;
use IPC::Run qw(run timeout);
use File::Slurp;
use Cwd;

app->static->paths->[0] = getcwd;


sub pdf2csv {
  my $pdf = shift;
  my $cols_col = shift;
  my $nbf = shift;

  my $ret = "class;temps;nom;cat;sexe;club\n";
  my @cmd = qw(pdftotext -layout - -);
  #my @cmd = qw(pdftotext -fixed 4 -layout - -);

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
    next if $class =~ /ABD/;
    my $temps = $fields[$temps_col]; chomp $temps;
    my $nom = $fields[$nom_col]; chomp $nom;
    if($prenom_col gt 0) {
      my $prenom = $fields[$prenom_col]; chomp $prenom;
      $nom .= " $prenom";
    }
    my $cat = $fields[$cat_col];
      chomp $cat;
      $cat =~ s/M([0-5])/V$1/;
      $cat =~ s/^[0-9]+ //;
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

any '/' => sub {
    my $self = shift;
    $self->redirect_to('/kikou');
};

any '/kikou' => sub {
    my $self = shift;
    $self->stash(
      presets => [
        { name => "Dansoft chronometrage",
          numbers => "[1, 4, 2, 0, 6, 7, 8, 9]"
        },
        { name => "Yaka chrono (ancien)",
          numbers => "[1, 5, 3, 0, 8, 0, 4, 9]",
        },
        { name => "Yaka chrono (2017)",
          numbers => "[1, 6, 3, 4, 8, 0, 5, 10]",
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
	my $content = pdf2csv($example->slurp, $cols, $nbf);
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
