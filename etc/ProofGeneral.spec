Summary:	Proof General, Emacs interface for Proof Assistants
Name:		ProofGeneral
Version:	2.2pre990922
Release:	1
Group:		Applications/Editors/Emacs
Copyright:	LFCS, University of Edinburgh
Url:		http://www.dcs.ed.ac.uk/proofgen/
Packager:	David Aspinall <da@dcs.ed.ac.uk>
Source:		http://www.dcs.ed.ac.uk/proofgen/ProofGeneral-2.2pre990922.tar.gz
BuildRoot:	/tmp/ProofGeneral-root
Patch:		ProofGeneral.patch
PreReq:		/sbin/install-info
Prefix:		/usr
BuildArchitectures: noarch

%description
Proof General is a generic Emacs interface for proof assistants,
suitable for use by pacifists and Emacs militants alike.
It is supplied ready-customized for LEGO, Coq, and Isabelle.
You can adapt Proof General to other proof assistants if you know a
little bit of Emacs Lisp.

To use Proof General, add the line

   (load-file "/usr/share/emacs/ProofGeneral/generic/proof-site.el")

to your .emacs file.

%changelog
* Wed Aug 25 1999 David Aspinall <da@dcs.ed.ac.uk>
  For 2.1 and 2.2pre series: made relocatable, added isar/ to package.

* Thu Sep 24 1998 David Aspinall <da@dcs.ed.ac.uk>
  First version.

%prep
%setup
%patch -p1
rm -f */*.orig

%build

%install
mkdir -p ${RPM_BUILD_ROOT}/usr/share/emacs/ProofGeneral

# Put binaries in proper place
mkdir -p ${RPM_BUILD_ROOT}/usr/bin
mv lego/legotags coq/coqtags ${RPM_BUILD_ROOT}/usr/bin

# Put info file in proper place.
mkdir -p ${RPM_BUILD_ROOT}/usr/info
mv doc/ProofGeneral.info doc/ProofGeneral.info-* ${RPM_BUILD_ROOT}/usr/info
gzip ${RPM_BUILD_ROOT}/usr/info/ProofGeneral.info ${RPM_BUILD_ROOT}/usr/info/ProofGeneral.info-*
# Remove duff bits
rm -f doc/dir doc/localdir doc/ProofGeneral.texi

cp -pr coq lego isa isar images generic ${RPM_BUILD_ROOT}/usr/share/emacs/ProofGeneral


%clean
if [ "X" != "${RPM_BUILD_ROOT}X" ]; then
    rm -rf $RPM_BUILD_ROOT
fi

%post
/sbin/install-info /usr/info/ProofGeneral.info.gz /usr/info/dir

%preun
/sbin/install-info --delete /usr/info/ProofGeneral.info.gz /usr/info/dir

%files
%attr(-,root,root) %doc BUGS INSTALL doc/*
%attr(-,root,root) /usr/info/ProofGeneral.info.gz
%attr(-,root,root) /usr/info/ProofGeneral.info-*.gz
%attr(-,root,root) /usr/bin/coqtags
%attr(-,root,root) /usr/bin/legotags
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral/coq
%attr(-,root,root) %dir /usr/share/emacs/ProofGeneral/coq/*
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral/lego
%attr(-,root,root) %dir /usr/share/emacs/ProofGeneral/lego/*
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral/isa
%attr(-,root,root) %dir /usr/share/emacs/ProofGeneral/isa/*
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral/isar
%attr(-,root,root) %dir /usr/share/emacs/ProofGeneral/isar/*
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral/images
%attr(-,root,root) %dir /usr/share/emacs/ProofGeneral/images/*
%attr(0755,root,root) %dir /usr/share/emacs/ProofGeneral/generic
%attr(-,root,root) %dir /usr/share/emacs/ProofGeneral/generic/*
