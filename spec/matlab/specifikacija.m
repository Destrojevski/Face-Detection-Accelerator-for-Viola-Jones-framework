%SPECIFIKACIJA UREĐAJA ZA PREBROJAVANJE LJUDI PREBROJAVANJEM LICA V1
%KORACI:
%1. Deklaracija i inicijalizacija  promjenljive koja predstavlja putanju do slike (puna putanja ako nije u
% matlab workspace folderu)
slikaPath = 'input.jpg';

%2. If naredba koja vrši provjeru da li slika inicijalizovana u prethodnom
%koraku postoji, ako ne postoji izbaci grešku.
if ~isfile(slikaPath)
    error('Greška: Slika nije pronađena na zadatoj putanji.');
end

%3. Učitavanje slike upotrebom naredbe imread
img = imread(slikaPath);

%3b. Konverzija slike u greyscale- Viola-Jones algoritam kao ulaz prima
%isključivo greyscaleovane slike kako bi mogao normalno i efikasno
%funkcionisati, moguć je rad i sa RGB slikama ali sa dosta manjom
%preciznošću. U MATLABu nije neophodna jer naredna naredba to odradi
%automatski
%ali je treba imati u vidu u daljoj implementaciji
%img = rgb2gray(img); 

%4. Kreiranje objekta tipa detektor lica HCC tipa. Moguće su navedene
%realizacije:
%1. Kreacija detektora lica korištenjem predefinisanog OpenCV FrontalFace
%default modela (veći recall, veća šansa za false positive detekcije, više se koristi)
%2. Kreacija detektora lica korištenjem predefinisanog OpenCV FrontalFace
%alt tree modela (manji recall, veća preciznost)
%3. Kreacija detektora lica korištenjem custom-made našeg modela
%odavde pocinje profajliranje,otkomentarisati narednu liniju za profiling
%profile on
detektorLica = vision.CascadeObjectDetector('haarcascade_frontalface_default.xml');

%5. Detekcija lica :
%Step metoda vrši detekciju lica na slici upotrebom objekta detekor lica
%tako što pretražuje sliku i traži regione koji liče na lica
%rezultat je promjenljiva koja sadrži koordinate pravougaonika oko svakog
%detektovanog lica.
bbox = step(detektorLica, img);

%6. Prebrojavanje detektovanih lica - pošto se svako detektovano lice
%smiješta u matricu bbox, veličina te matrice ujedno predstavlja i broj
%detektovanih lica
brojLica = size(bbox, 1);
%ovdje prestaje profajliranje,otkomentarisati narednu liniju za profiling
%profile off
%7. Označavanje detektovanih lica (opcioni dio projekta, moguća QoL
%opcija radi verifikacije ispravnosti rada)
oznacenaSlika = insertObjectAnnotation(img, 'rectangle', bbox, 'Face');


%8. Ispis broja detektovanih lica
disp(['Broj prebrojanih lica: ' num2str(brojLica)])


%9. Prikaz slike sa označenim licima (opcioni dio projekta, moguća QoL
%opcija radi verifikacije ispravnosti rada)
imshow(oznacenaSlika);
title(['Broj prebrojanih lica: ' num2str(brojLica)]);
outputPath = 'oznacena_slika.jpg';
imwrite(oznacenaSlika, outputPath);
disp(['Rezultati sačuvani u: ', outputPath]);
%otkomentarisati narednu liniju za profiling
%profsave
