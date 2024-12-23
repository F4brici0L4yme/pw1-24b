#!/usr/bin/perl -w

use strict;
use warnings;
use utf8;
use CGI;
use HTML::Entities;
use File::Temp qw(tempfile);
use File::Path qw(make_path);

my $cgi = CGI->new;

my $java_code_main        = $cgi->param('java_code_main');
my $java_code_inheritance = $cgi->param('java_code_inheritance');
my $java_code_interface   = $cgi->param('java_code_interface');
my $java_code_class       = $cgi->param('java_code_class');
my $java_comp_aggre       = $cgi->param('java_comp_aggre');
my $java_dependencies     = $cgi->param('java_dependencies');

sub generate_uml_class {
    my ($java_code) = @_;

    my @lines = split /\n/, $java_code;  # Divide el código Java en líneas
    my @uml_contents;                   # Almacena las partes extraídas para el UML
    my $current_class = '';             # Para rastrear la clase actual
    my $class = '';

    foreach my $line (@lines) {
        
        next if $line =~ /^\s*(\/\*|\*|\/\/)/;
        
        if ($line =~ /^\s*(?:public|private)\s+(abstract\s)?class\s+(.+?)\s*\{/) {
            
            if ($current_class) {
                push @uml_contents, "}\n";
            }

            my $abstract = $1 // '';
            my $content = $2;
            $current_class =  "$abstract"."class $content {";
            push @uml_contents, $current_class;
            
            $class = $content;

        }

        # Buscar atributos
        elsif ($line =~ /^\s*(public|private|protected)\s+(.*?);/) {
            my $visibility = $1;  # Captura public, private o protected
            my $content = $2;     # Captura el contenido después de la visibilidad
            
            my $prefix = $visibility eq 'public'    ? '+' :
                        $visibility eq 'private'   ? '-' :
                        $visibility eq 'protected' ? '#' : '';

            my $is_static = '';
            if ($content =~ /\bstatic\s+/) {
                $is_static = '{static} ';
                $content =~ s/\bstatic\s+//g;  # Elimina la palabra static del contenido
            }

            # Ignorar la palabra final si está presente
            $content =~ s/\bfinal\s+//g;

            # Capturar tipo de dato, nombre y valor
            if ($content =~ /^([\w<>,\[\]\s]+)\s+(\w+)(?:\s*=\s*(.+))?$/) {
                my $type = $1;         # Captura el tipo de dato
                my $name = $2;         # Captura el nombre del atributo
                my $value = $3 // '';  # Captura el valor si existe (o vacío)

                
                $value =~ s/^["']//g;
                $value =~ s/["']$//g;

                
                my $uml_line = "\t$prefix$is_static$name: $type";
                $uml_line .= " = $value" if $value;  # Agregar el valor si existe

                push @uml_contents, $uml_line;
            }
        }

        elsif ($line =~ /^\s*(public\s+)?\Q$class\E\((.*?)\)\s*\{/) {
            my $constructor_name = $class;  # El nombre del constructor es igual al nombre de la clase
            my $parameters = $2;            # Los parámetros del constructor
            
            # Agregar el constructor al contenido UML
            push @uml_contents, "\t+$constructor_name($parameters) : void";
        }

        # Buscar métodos
        elsif ($line =~ /^\s*(public|private|protected)\s+(.*?\{)/) {
            my $visibility = $1;  # Captura public, private o protected
            my $content = $2;     # Captura el contenido después de la visibilidad

           
            my $prefix = $visibility eq 'public'    ? '+' :
                        $visibility eq 'private'   ? '-' :
                        $visibility eq 'protected' ? '#' : '';

            
            my $is_static = '';
            if ($content =~ /\bstatic\s+/) {
                $is_static = '{static} ';
                $content =~ s/\bstatic\s+//g;  
            }

            
            my $is_abstract = 0;
            if ($content =~ /\babstract\s+/) {
                $is_abstract = 1;
                $content =~ s/\babstract\s+//g;  
            }

            
            if ($is_static && $is_abstract) {
                warn "Error: un método no puede ser 'static' y 'abstract' al mismo tiempo.\n";
                return; 
            }

            # Capturar tipo de retorno, nombre del método, y parámetros
            if ($content =~ /^([\w<>,\[\]\s]+)\s+(\w+)\((.*?)\)\s*\{/) {
                my $return_type = $1;          # Captura el tipo de retorno (incluye genéricos y arreglos)
                my $method_name = $2;         # Captura el nombre del método
                my $parameters = $3;          # Captura los parámetros

                # Construir la representación UML del método
                push @uml_contents, "\t$prefix$is_static$method_name($parameters) : $return_type";
            }

        }
    }
    
    # Cerrar la clase si fue abierta
    push @uml_contents, "}" if $current_class;

    # Combinar los contenidos extraídos en un bloque de UML
    my $uml = join("\n", @uml_contents);
    return $uml;
}


sub generate_uml_interface {
    my ($java_code) = @_;

    my @lines = split /\n/, $java_code;  
    my @uml_contents;                    
    my $inside_interface = 0;            

    foreach my $line (@lines) {
        
        next if $line =~ /^\s*$/ || $line =~ /^\s*(\/\*|\*|\/\/)/;

        # Capturar la declaración de la interfaz
        if ($line =~ /^\s*(?:public\s+)?interface\s+(\w+)/) {
            my $interface_name = $1;
            push @uml_contents, "interface $interface_name {";
            $inside_interface = 1;  # Marcar que estamos dentro de una interfaz
            next;
        }

        # Procesar atributos (siempre son static y tienen valor asignado)
        if ($inside_interface && $line =~ /^\s*(\w+)\s+(\w+)\s*=\s*([^;]+);/) {
            my $type = $1;            # Tipo del atributo
            my $name = $2;            # Nombre del atributo
            my $value = $3;           # Valor del atributo
            $value =~ s/['"]//g;      # Eliminar comillas si las tiene

            # Agregar atributo al UML (siempre static)
            push @uml_contents, "\t+{static} $name: $type = $value";
            next;
        }

        # Procesar métodos con su nombre, parámetros y tipo de retorno
        if ($inside_interface && $line =~ /^\s*(\w+)\s+(\w+)\((.*?)\)\s*;\s*$/) {
            my ($return_type, $method_name, $params) = ($1, $2, $3);

            # Agregar método al UML
            push @uml_contents, "\t+$method_name($params): $return_type;";
            next;
        }

        # Detectar el cierre de una interfaz
        if ($line =~ /^\s*}/ && $inside_interface) {
            push @uml_contents, "}\n";
            $inside_interface = 0;  # Marcar que hemos salido de la interfaz
            next;
        }
    }

    # Combinar y devolver el UML
    return join("\n", @uml_contents);
}

sub generate_uml_aggre_comp {
    my ($input) = @_;  # Recibe el texto de entrada
    my @uml_lines;     # Array para almacenar las líneas generadas

    # Dividir el texto de entrada por líneas para analizar cada una
    my @lines = split /\n/, $input;

    foreach my $line (@lines) {
        # Ignorar líneas vacías o con solo espacios
        next if $line =~ /^\s*$/;

        # Detectar si la línea contiene @Agregacion o @Composicion (sin importar mayúsculas, minúsculas o tildes)
        if ($line =~ /\@(?:Agregaci[oó]n|Composici[oó]n):\s*(.*?)\s+tiene\s+(.*)/i) {
            my $relation_type = $1;    # Tipo de relación (lo que sigue a @Agregacion o @Composicion)
            my $start_part    = $2;    # Lo que sigue después de 'a'

            # Determinar el símbolo de relación UML
            my $symbol = $line =~ /\@Agregaci[oó]n/i ? 'o--' : '*--';

            # Extraer información del inicio de la relación (antes de 'a')
            if ($relation_type =~ /^(.*?)\s+(\S+)$/) {
                my $start_name   = $1;  # Nombre inicial
                my $start_card   = $2;  # Cardinalidad inicial

                # Extraer información del final de la relación (después de 'a')
                if ($start_part =~ /^(\S+)\s+(.*)$/) {
                    my $end_card   = $1;  # Cardinalidad final
                    my $end_name   = $2;  # Nombre final

                    # Generar la línea UML y agregarla al array
                    my $uml_line = "$start_name \"$start_card\" $symbol \"$end_card\" $end_name";
                    push @uml_lines, $uml_line;
                }
            }
        }
    }

    return join("\n",@uml_lines);  # Devolver las líneas generadas
}

sub generate_uml_dependencies {
    my ($input) = @_;  # Recibe el texto de entrada
    my @uml_lines;     # Array para almacenar las dependencias generadas

    # Dividir el texto de entrada por líneas para analizar cada una
    my @lines = split /\n/, $input;

    foreach my $line (@lines) {
        # Buscar el patrón @Dependencia (sin importar mayúsculas/minúsculas)
        if ($line =~ /\@dependencia\s*:\s*(\S+)\s+a\s+(\S+)/i) {
            my $class1 = $1;  # Lo que está antes de "a"
            my $class2 = $2;  # Lo que está después de "a"

            # Formatear y almacenar la dependencia
            push @uml_lines, "$class1 --> $class2";
        }
    }

    return join("\n",@uml_lines);  # Retornar el array con las dependencias
}

# Generar UML dinámico para hacer el diagrama
my $uml_content = '@startuml'."\n";
$uml_content .= 'hide class circle'."\n";
$uml_content .= 'hide interface circle'."\n";
$uml_content .= 'skinparam classAttributeIconSize 0'."\n";
$uml_content .= generate_uml_class($java_code_inheritance) ."\n";
$uml_content .= generate_uml_interface($java_code_interface) ."\n";
$uml_content .= generate_uml_class($java_code_class) ."\n\n";
$uml_content .= generate_uml_class($java_code_main) ."\n";
$uml_content .= generate_uml_aggre_comp($java_comp_aggre) ."\n";
$uml_content .= generate_uml_dependencies($java_dependencies) ."\n";
$uml_content .= "\n".'@enduml'."\n";

# Ruta para guardar el archivo .puml
my $output_dir = "/usr/lib/puml_files/";
my $filename   = "archivo.puml";
my $filepath   = "$output_dir/$filename";

# Asegurar que el directorio exista
make_path($output_dir) unless -d $output_dir;

# Guardar el archivo UML
if (open(my $fh, '>', $filepath)) {
    print $fh $uml_content;
    close($fh);
}

# Devolver la salida
print $cgi->header('application/json');

# Ruta al script que se quiere ejecutar
my $script_path = 'fast_diagram.pl';

# Ejecuta el script
my $exit_status = system("perl $script_path");

# Verifica si se ejecutó correctamente
if ($exit_status == 0) {
    print "Content-type: text/plain\n\n";
    print "El script se ejecutó exitosamente.\n";
} else {
    print "Content-type: text/plain\n\n";
    print "Hubo un error al ejecutar el script.\n";
}

