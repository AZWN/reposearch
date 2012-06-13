package svn;


import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.util.ArrayList;
import java.util.Collection;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.tmatesoft.svn.core.SVNDirEntry;
import org.tmatesoft.svn.core.SVNErrorMessage;
import org.tmatesoft.svn.core.SVNException;
import org.tmatesoft.svn.core.SVNLogEntry;
import org.tmatesoft.svn.core.SVNLogEntryPath;
import org.tmatesoft.svn.core.SVNNodeKind;
import org.tmatesoft.svn.core.SVNProperties;
import org.tmatesoft.svn.core.SVNURL;
import org.tmatesoft.svn.core.internal.io.dav.DAVRepositoryFactory;
import org.tmatesoft.svn.core.internal.io.fs.FSRepositoryFactory;
import org.tmatesoft.svn.core.internal.io.svn.SVNRepositoryFactoryImpl;
import org.tmatesoft.svn.core.io.SVNRepository;
import org.tmatesoft.svn.core.io.SVNRepositoryFactory;

import webdsl.generated.domain.Entry;

public class Svn {
    private static StringBuilder logBuilder = new StringBuilder();

    public static void main(String[] args){
        test();
    }

    public static void test(){
        String repo = "https://svn.strategoxt.org/repos/reposearch/reposearch/";
        updateFromRevOrCheckout(repo, 65);
    }

    public static RepoTaskResult updateFromRevOrCheckout(String user,String repo, long rev) {
        return updateFromRevOrCheckout("https://github.com/"+user+"/"+repo, rev);
    }
    public static RepoTaskResult checkout(String user,String repo) {
        return checkout("https://github.com/"+user+"/"+repo);
    }

    private static final long latestRevision = -1;

    public static RepoTaskResult checkout(String repo) {
        return updateFromRevOrCheckout(repo, -10);
    }

    //It returns a RepoTaskResult object with:
    // -if fromRev is not the latest: non-null file lists with updated/deleted file representations.
    // -if fromRev < 1 : It performs a checkout and returns a RepoTaskResult object with all files in HEAD revision
    // -if fromRev is the latest: null file lists (no need to update)
    public static RepoTaskResult updateFromRevOrCheckout(String repoUrl, long fromRev) {
        String url = repoUrl;

        setupLibrary();
        SVNRepository repository = null;
        try {
            repository = SVNRepositoryFactory.create(SVNURL.parseURIEncoded(url));

            //long headRevRepoRoot = repository.getLatestRevision();
            long repoUrlHeadRev = repository.getDir("", latestRevision, true, null).getRevision();

            if (fromRev >= repoUrlHeadRev) {
                log("Skipped update for repo: " + repoUrl + ". This one is already at head revision");
                return new RepoTaskResult(null, null, repoUrlHeadRev);
            }

            SVNNodeKind nodeKind = repository.checkPath("", latestRevision);

            if (nodeKind == SVNNodeKind.NONE) {
                log("There is no entry at '" + url + "'.");
                throw new SVNException(SVNErrorMessage.UNKNOWN_ERROR_MESSAGE);
            } else if (nodeKind == SVNNodeKind.FILE) {
                log("The entry at '" + url + "' is a file while a directory was expected.");
                throw new SVNException(SVNErrorMessage.UNKNOWN_ERROR_MESSAGE);
            }




            List<Entry> entriesForAddition = new ArrayList<Entry>();
            List<String> entriesForRemoval = new ArrayList<String>();

            if (fromRev < 1) {
                log("Checkout: " + repoUrl);
                addEntryRecursive("", repository, entriesForAddition);
            } else {
                log("Updating: " + repoUrl + " from" + fromRev + " to HEAD");
                updateToRevision(repository, fromRev+1, entriesForAddition, entriesForRemoval);
            }

            return new RepoTaskResult(entriesForAddition, entriesForRemoval, repoUrlHeadRev);
        } catch (SVNException svne) {
            svne.printStackTrace();
            return null;
        }
    }

    private static void updateToRevision(SVNRepository repository, long start, List<Entry> entriesForAddition, List<String> entriesForRemoval) throws SVNException{
        Collection<?> logEntries = null;

        String repositoryRootUrl = repository.getRepositoryRoot(false).toString();

        logEntries = repository.log( new String[] { "" } , null , start , latestRevision , true , true );
        Iterator<?> logs = logEntries.iterator();
        Map<?,?> changedPaths;
        Set<String> toAdd = new HashSet<String>(), toRemove = new HashSet<String>();
        while(logs.hasNext()){
            changedPaths = ((SVNLogEntry) logs.next()).getChangedPaths();

            for ( Iterator<?> pathEntries = changedPaths.keySet().iterator( ); pathEntries.hasNext( ); ) {
                SVNLogEntryPath entryPath = ( SVNLogEntryPath ) changedPaths.get( pathEntries.next( ) );

                if ( entryPath.getKind().equals(SVNNodeKind.DIR) &&
                     entryPath.getType() == SVNLogEntryPath.TYPE_DELETED ) {
                     toRemove.add(entryPath.getPath());
                }

                if ( !entryPath.getKind().equals(SVNNodeKind.FILE)
                  || !entryPath.getPath().startsWith( repository.getRepositoryPath("") ) )
                        continue; //ignore entry paths that dont represent files or do not reside in the chosen repository directory

                switch (entryPath.getType()) {
                case SVNLogEntryPath.TYPE_ADDED : toAdd.add(entryPath.getPath());
                                                  break;
                case SVNLogEntryPath.TYPE_MODIFIED: //modified -> remove and add
                case SVNLogEntryPath.TYPE_REPLACED: toAdd.add(entryPath.getPath());
                                                    toRemove.add(entryPath.getPath());
                                                    break;
                case SVNLogEntryPath.TYPE_DELETED: toRemove.add(entryPath.getPath());
                                                   toAdd.remove(entryPath.getPath());
                                                   break;
                default:
                    break;
                }
            }
        }
        StringBuilder sb = new StringBuilder("Update summary for " + repositoryRootUrl + " from r" + start + " to HEAD (modified files will be deleted and added):");
        sb.append("\n--------------------------------");
        for (String path : toRemove) {
            entriesForRemoval.add( repositoryRootUrl+repository.getRepositoryPath(path) );
            sb.append("\n- ");
            sb.append(path);
        }
        for (String path : toAdd) {
            getFile(path, repository, entriesForAddition);
            sb.append("\n+ ");
            sb.append(path);
        }
        sb.append("\n--------------------------------");
        log(sb.toString());
    }


    private static void addEntryRecursive(String dir,SVNRepository repository,List<Entry> entries) throws SVNException {
        SVNProperties props = null;
        Collection<?> nullcol = null;
        log("getdir: " + repository.getLocation().getPath() + "/" + dir);
        Collection<?> col = repository.getDir(dir, latestRevision, props, nullcol);
        @SuppressWarnings("rawtypes")
        Iterator i = col.iterator();
        //System.out.println(i.hasNext());
        while(i.hasNext()){
            SVNDirEntry o = (SVNDirEntry) i.next();
            //System.out.println(o.getName());
            //System.out.println(o.getKind());
            if(o.getKind()==SVNNodeKind.DIR){
                //System.out.println("dir: "+o.getName());
                addEntryRecursive(dir+o.getName()+"/",repository, entries);
                continue;
            }
            else{
                //System.out.println("file: "+o.getName());
                try {
                    getFile(dir+o.getName(), repository, entries);
                } catch (SVNException e) {
                    // TODO Auto-generated catch block
                    e.printStackTrace();
                }
            }
        }
    }


    private static void getFile(String path, SVNRepository repository, List<Entry> entries) throws SVNException{

        String fileName = path.substring( path.lastIndexOf('/') +1);
        String url = repository.getRepositoryRoot(false).toString() + repository.getRepositoryPath(path);
        String content = null, contentFixed = null;
        boolean isBinFile = true;
        Entry c = new Entry();

        c.setNameNoEventsOrValidation(fileName);
        c.setUrlNoEventsOrValidation(url);
        if(! (fileName.endsWith(".zip")
        ||fileName.endsWith(".tbl")
        ||fileName.endsWith(".png")
        ||fileName.endsWith(".jpg")
        ||fileName.endsWith(".bmp")
        ||fileName.endsWith(".jar") ) ) {

            ByteArrayOutputStream out = new ByteArrayOutputStream();

            if(repository.checkPath(path, latestRevision).equals(SVNNodeKind.NONE)){
                log("Failed to download (possibly deleted) file: " + url);
                return;
            }
            repository.getFile(path, latestRevision, null, out);

            //Use utils.File as container for converting to String with proper encoding
            utils.File f = new utils.File();
            ByteArrayInputStream in = null;
            try{
                in = new ByteArrayInputStream(out.toByteArray());
                f.setContentStream(in);

                content = f.getContentAsString();
                contentFixed = fixEncoding( content );
                isBinFile = ( contentFixed.length() < 1 && !contentFixed.equals( content ) ) ;
            } catch( IOException ex){
                ex.printStackTrace();
            } finally {
                try{
                    if (in != null)
                        in.close();
                    if(out != null)
                        out.close();
                } catch (java.io.IOException ex){
                    log("file close exception during getFile reposearch:");
                    ex.printStackTrace();
                }
            }
        }
        if (isBinFile){
            c.setContentNoEventsOrValidation( addLines("BINFILE") );
        } else {
            c.setContentNoEventsOrValidation( addLines( contentFixed ) );
        }
        entries.add(c);


    }


    /*
     * Initializes the library to work with a repository via
     * different protocols.
     */
    private static void setupLibrary() {
        /*
         * For using over http:// and https://
         */
        DAVRepositoryFactory.setup();
        /*
         * For using over svn:// and svn+xxx://
         */
        SVNRepositoryFactoryImpl.setup();
        /*
         * For using over file:///
         */
        FSRepositoryFactory.setup();
    }

    private static String addLines(String content){
          content = content.replaceAll("\n\r|\r\n|\r", "\n");
          String[] lines = content.split("\n");
          StringBuilder sb = new StringBuilder();
          int cnt = 1;
          for (String line : lines) {
            sb.append(cnt++ + " " + line + "\n");
          }
          return sb.toString().trim();

    }

    public static String fixEncoding(String input){
      try {
        int errors = 0;
        byte[] bytes = input.getBytes("UTF-8");
        for (int pos = 0; pos < bytes.length; pos++) {
          if ((bytes[pos] & 0x80) != 0) {
            bytes[pos] = (byte) '?';
            if (errors++ > 100){
                return "";
            }
          }
        }
        if(errors > 0)
          return new String(bytes);
        else
          return input;
      } catch (UnsupportedEncodingException e) {
        // Impossible, throw unchecked
        throw new IllegalStateException("No Latin1 or UTF-8: " + e.getMessage());
      }
    }

    private static void log(String msg){
        System.out.println("Reposearch: " + msg);
        logBuilder.append(new java.util.Date());
        logBuilder.append(": ");
        logBuilder.append(msg);
        logBuilder.append("\n");

    }
    public static String getLog(){
        String toReturn = logBuilder.toString();
        logBuilder = new StringBuilder();
        return toReturn;
    }
}