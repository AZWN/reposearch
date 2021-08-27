module manage/manage-ui

imports built-in
imports reposearch
imports language-construct/language-construct-data
imports language-construct/language-construct-ui
imports manage/manage-data
imports project/project
imports repository/repository
imports request/request
imports search/search-ui

imports elib/elib-bootstrap/lib

section pages

  page manage() {
    init {
      if( langConsRenewSchedule.enabled == null ) {
        langConsRenewSchedule.enabled := true;
      }
      if(activeTheme.theme == null){
      	activeTheme.theme := findBootstrapTheme("bootstrap");
      }
    }
    title { output( "Manage Reposearch | Reposearch" ) }
    mainResponsive( "Projects" ) {
      manageRefresh()
      themeChooser
      manageRequestReceipts()
      placeholder "requestsPH" {
        showRequests()
      }
      manageProjects()

      manageMessage( messages.frontPageMsg , "Manage Frontpage Message", true)
      
      manageMessage( messages.downloadMsg , "Manage Download Page", false)
      
      misc()
      
      logMessage()
    }
  }

  page searchStats() {
    var startDate := if( manager.newWeekMoment!=null ) manager.newWeekMoment else now();
    var projectsInOrder := from Project order by searchCount desc;
    title { output( "Search statistics | Reposearch" ) }
    mainResponsive( "Projects" ) {
      showSearchStats()
      submitlink action {SearchStatistics.clear();} { buttonMini { "Reset global statistics" } }
      header {"Search counts per project"}
      tableStriped {
        theader{
          row{ th[class="span4"]{ "Project name" } th[class="span2"]{ "total"} th[class="span2"]{ "this week" } th[class="span3"]{ "since" } th[class="span2"]{ "reset" }}
        }
          
        for( pr : Project in projectsInOrder order by pr.weeklySearchCount desc ) {
          searchCountInTable( pr )
        }
      }
      form {
        "Control the day at which this week started (next week starts 7 days later) : " input( startDate )
        submitlink action{manager.newWeekMoment := startDate;}{ buttonMini{"set"} }
      } <br />
      submitlink action {for( pr : Project ) { pr.resetSearchCount(); }} { buttonMini{ "Reset search statistics for all projects" } }
    }
  }
  
  page fileUpload( pr : Project){
    var file : File
    title{ "Upload repository file" }    
    mainResponsive( "Projects" ){
      manageContainer( "File repository for " + pr.displayName ) {
	      inlForm{
          formEntry( "Zipped file" ){
            input( file )
          }
          formActions{
            submit action{ return manage(); } { "cancel" } " "
            submit action{
              validate( (file != null ) , "Select a valid file");
              pr.repos.add( createNewRepo( "", false, file ) );
              return manage();
            } {  "upload" }
          }
	        
	      }
      }
    }
  }

section templates

template themeChooser(){
	var allowed := from BootstrapTheme order by name;
	init{
		if(allowed.length < 2){
			initThemes();
			allowed := from BootstrapTheme order by name;
		}
		
	}
	panel("Choose theme"){
		horizontalForm{
			controlGroup("Theme"){ input(activeTheme.theme, allowed) }
			
			formActions{
				submitlink action{}[class="btn btn-primary"]{"Save"}
			}
		}
		
	}
}

  define manageRequestReceipts() {
    var addresses : String := manager.adminEmails;
    manageContainer( "Administrator email addresses" ) {
	    inlForm{
	      formEntry( "Addresses which will receive a notification upon a request" ){ input( addresses ) }
	      validate( validateEmailList( addresses ) ,"Email addresses need to be seperated by a comma, without whitespace e.g. 'foo@bar.com,bar@foo.com'" )
	      div{ submitlink action{manager.adminEmails := addresses;}{ buttonPrimaryMini{"save"} } }
	    }
    }
  }

  define ajax showProject( pr : Project ) {
    wellSmall{ 
	    searchCount( pr )
	    manageContainerNested("Repositories"){
		    placeholder "reposPH" + pr.name{
		      showRepos( pr )
		    }
		    placeholder "addRepoPH" + pr.name{
	       addRepoBtn( pr )
	      }
	    }
	    manageContainerNested("Language Constructs"){
		    manageLangConstructs( pr )
	    }	 
    }       
  }

  define manageProjects() {
    var p := "";
    var projects := from Project;
    
    manageContainer( "Manage Projects" ) {
      manageContainerNested( "New Project" ) {
	      inlForm {
	        controlGroup( "Project Name" ) { input( p ) }
	        submitlink action{Project{name:=p} .save();} { buttonPrimaryMini{"Add new project"} }
	      }
      }
      gridRow{ gridCol(12){
        filterProject( projects )
      } }
      gridRow{ gridCol(12){
        placeholder "projectsArea" {
          showManageProjects( projects )
        }
      } }
    }    
  }

  define ajax showManageProjects(projects : List<Project>){
    for( pr:Project in projects order by pr.displayName ) {
        <h5> 
          submitlink( pr.name, showProject( pr ) ) [ajax] 
          pullRight{"[" submitlink( "remove project", removeProject( pr ) ) "]*"}
        </h5>
        <div id=URLFilter.filter( "projectPH"+pr.name ) class="webdsl-placeholder" style="display: none;">showProject( pr ) </div>
    }
    "* Removal of a project may take over a minute, please be patient."
    <br />
      
    action showProject( pr : Project ) {
      visibility( "projectPH"+pr.name, toggle );
    }
    action ignore-validation removeProject( pr : Project ) {
      for( r:Repo in pr.repos ) {
        deleteAllRepoEntries( r );
        r.delete();
      }
      pr.langConstructs.clear();
      settings.projects.remove( pr );
      pr.delete();
      settings.reindex := true;
      return manage();
    }
  }
  
  define searchCount( pr : Project ) {
    "searches this week(since " output( manager.newWeekMoment ) "): " <b>output( pr.weeklySearchCount ) </b>
    <br />
    "searches total(since " output( pr.countSince ) "): " <b>output( pr.searchCount ) </b> " " resetSearchCountLink(pr)
    <br />
  }

  define searchCountInTable( pr : Project ) {
    row {
      column{ output( pr.displayName ) }
      column{ <b>output( pr.searchCount ) </b> }
      column{ <b>output( pr.weeklySearchCount ) </b> }
      column{ output( pr.countSince ) }
      column{ resetSearchCountLink(pr) }
    }
  }
  
  define resetSearchCountLink( pr : Project ) {
  	submitlink action{pr.resetSearchCount();} { buttonMini{ "reset" } }
  }

  define manageMessage( msg : Ref<WikiText>, title : String, centered : Bool ) {
    var msgText := msg;
    manageContainer( title ){
      inlForm{
        controlGroup( "Message" ){ input( msgText ) [oninput="$(this).keyup();", onkeyup=updateMsgPreview( msgText )] }
        div { submitlink action{msg := msgText; messages.save();}{ buttonPrimaryMini{"save"} } }
      }
      <h5>"Preview"</h5>
      wellSmall{
        placeholder ""+title { msgPreview( msgText, centered ) }
      }
    }
    
    action ignore-validation updateMsgPreview( d : WikiText ) {
      replace( ""+title, msgPreview( d, centered ) );
    }
  }

  define ajax msgPreview( d : WikiText, centered : Bool ) {
  	if(centered)  { <center> rawoutput( d ) </center> }
  	else { rawoutput( d ) }
  }

  define logMessage() {
    manageContainer( "Reposearch Log" ) { 
      placeholder "log" { showLog() }
      "Auto-refreshes every 5 seconds, but you can also "
      submitlink action{replace( "log", showLog() );} [id = "autoRefresh", ajax]{ buttonMini{"force it"} }
      <script>
      var refreshtimer;
      function setrefreshtimer() {
        clearTimeout( refreshtimer );
        refreshtimer = setTimeout( function() {
          $ ( "#autoRefresh" ).click();          
          setrefreshtimer();
        },5000 );
      }
      setrefreshtimer();
      
      var objDiv = document.getElementById("log");
      objDiv.scrollTop = objDiv.scrollHeight; 
      </script>
    }
  }
  
  define misc(){
    var fr := ( from Repo where project is null );
    
    action ignore-validation removeFRs(){
    	for( r:Repo in fr ) {
            deleteAllRepoEntries( r );
            r.delete();
          }
          return manage();
    }
    
    manageContainer( "Misc" ){
      submitlink action { deleteUnlinkedConstructMatches(); }{ buttonMini{ "Delete unlinked construct matches" } }
      if( fr.length > 0 ) {
        <br />
        submitlink removeFRs(){ buttonMini{ "Remove foreign Repo's(" output( fr.length ) ")"} } " (Repo entities where project == null)"
      }
    }
  }

  define manageRefresh() {
    placeholder "refreshManagement" { refreshScheduleControl() } <br />
  }

  define ajax refreshScheduleControl() {
    var now := now();
    manageContainer("Manage Refresh Scheduling") {
      gridRow{ gridCol(8){
	      tableStriped{
	        row{ column{<strong>"Refresh scheduling:"</strong>}         column{ submitlink action{resetSchedule();} { buttonMini{"reset"} } } }
	        row{ column{"Server time"}                                  column{ output( now ) } }
	        row{ column{"Last refresh(all repos)"}                      column{ if( manager.lastInvocation != null ) { output( manager.lastInvocation ) } else {"unkown"} } }
	        row{ column{"Next scheduled refresh(all repos)"}            column{ output( manager.nextInvocation ) " " shiftScheduleBtn(-24,"-1d") shiftScheduleBtn(-1, "-1h" ) shiftScheduleBtn( 1, "+1h" ) shiftScheduleBtn(24, "+1d") } }
	        row{ column{"Auto refresh interval(hours)"}                 column{ form{ input( manager.intervalInHours ) [style := "width:3em;"]  submitlink action{manager.save(); replace( "refreshManagement", refreshScheduleControl() );}{ buttonMini{"set"} } } } }
	        row{ column{<strong>"Instant refresh management:"</strong>} column{ }}
	        row{ column{"Update all repos to HEAD: "}                   column{ submitlink action{refreshAllRepos();         replace( "refreshManagement", refreshScheduleControl() );} { buttonMini{"refresh all"} } } }
	        row{ column{"Force a fresh checkout for all repos: "}       column{ submitlink action{forceCheckoutAllRepos();   replace( "refreshManagement", refreshScheduleControl() );} { buttonMini{"force checkout all"} } } }
	        row{ column{"Cancel all scheduled refresh/checkouts: "}     column{ submitlink action{cancelScheduledRefreshes();replace( "refreshManagement", refreshScheduleControl() );} { buttonMini{"cancel all"} } } }
	        row{ column{"Auto renewal of language construct matches: "} column{ "enabled? " form{ input( langConsRenewSchedule.enabled ) submitlink action{langConsRenewSchedule.save(); replace( "refreshManagement", refreshScheduleControl() );} { buttonMini{"apply"} } } }}
	      }      
	    } }
    }
  }

  define ajax addRepoBtn( pr : Project ) {
    submitlink action { replace( "addRepoPH" + pr.name, addRepo( pr ) );} { buttonMini{"Add repository" } }
  }

  define ajax showRepos( pr : Project ) {
    for( r:Repo in pr.repos ) {
      showRepo( pr,r )
    }
  }
  
  define shiftScheduleBtn( shiftInHours : Int, btnText : String){
  	submitlink action{manager.shiftByHours( shiftInHours ); replace( "refreshManagement", refreshScheduleControl() );} { buttonMini{ output(btnText) } }
  }

  define ajax addRepo( pr : Project ) {
    var gu:String
    var gr:String
    var file:File
    var isTag:=false
    var n:URL
    manageContainerNested("New Repository"){
	    inlForm{
        navigate( fileUpload(pr) ){ "Upload a zipfile"} <br />
        <br /> "-OR-" <br />
	      formEntry( "SVN or github URL" ){
	        input( n ) <br /> 
	        input( isTag ) " This is a tag on github" 
	      }      
	      div{
	        submitlink action{ replace( "addRepoPH" + pr.name, addRepoBtn( pr ) );} { buttonMini{"Cancel"} } " "
	        submitlink action{
	          validate( ( n != null && n.length() > 0 ), "Enter a valid repository URL"); 
	          pr.repos.add( createNewRepo( n, isTag, file ) );
	          replace( "addRepoPH" + pr.name, addRepoBtn( pr ) );
	          replace( "reposPH" + pr.name, showRepos( pr ) );
	        } { buttonPrimaryMini{ "Add repository" } }
	      }
	    }
    }
  }

  define showRepo( pr:Project, r:Repo ) {
  	
  	action ignore-validation removeRepo(){
  		deleteAllRepoEntries( r ); pr.repos.remove( r ); replace( "reposPH" + pr.name, showRepos( pr ) );
  	}
    output( r ){
      div{
        if( r.refresh ) {
          if( r.refreshSVN ) { "UPDATE TO HEAD SCHEDULED" }
          else { "CHECK OUT SCHEDULED" }
          submitlink action{cancelQueryRepo( r ); replace( "reposPH" + pr.name,showRepos( pr ) ); } { buttonMini{"Cancel"} }
        } else{
          submitlink action{queryRepo( r ); replace( "reposPH" + pr.name,showRepos( pr ) );} { buttonMini{"Update if HEAD > r" output( r.rev )} }
          submitlink action{queryCheckoutRepo( r ); replace( "reposPH" + pr.name,showRepos( pr ) );} { buttonMini{"Force checkout HEAD"} }
        }
        submitlink removeRepo(){ buttonMini{"Remove*"} }
        submitlink action{return skippedFiles( r );}{ buttonMini{"skipped files"} }
      }
      if( r.error ) {
        div {"ERROR OCCURRED DURING REFRESH"}
      }
    }
  }

  define ajax showRequests() {
  	var requests := from Request;
  	if ( requests.length > 0 ) {
	    manageContainer( "Pending Requests" ) {
		    for( r:Request order by r.project ) {
		      showRequest( r )
		    }
	    }
    }
  }

  define showRequest( r : Request ) {
    var project := r.project;
    var repo : URL := r.svn;
    var isGithubTag := r.isGithubTag;
    var existing : List<Project>;
    var targetProject : Project;
    var reason : Text := "";
    alertSuccess {
      "requester: " output( r.submitter )
      inlForm{
        formEntry( "Project name" ){ input( project ) }
        formEntry( "Repository location" ){ input( repo ) }   
        formEntry( "is Github tag?" ){ input( isGithubTag ) }   
        formEntry( "Reason in case of rejection" ){ input( reason ) }           
        submit action{
          r.delete();
          replace( "requestsPH", showRequests() );
          sendRequestRejectedMail( r, reason );
        }{"reject(deletes request)"}
        submit action{
          existing := from Project where name = ~project;
          if( existing.length != 0 ) {
            targetProject := existing[0];
          } else {
            targetProject := Project{ name:=project };
          }
          targetProject.save();
          targetProject.repos.add( createNewRepo( repo, isGithubTag, null ) );

          sendRequestAcceptedMail( r );
          r.delete();
          return manage();
        }{"add to new/existing project"}
      }
    }
  }

  page skippedFiles( r : Repo ) {
    init {
      return search( r.project.name , "BINFILE" );
    }
  }

  define ajax showLog() {
    init {updateLog();}
    wellSmall {
      small{ <pre> rawoutput( manager.log ) </pre> }
    }
  }

  define override logout() {
    "Logged in as: " output( securityContext.principal.name )
    form {
      submitlink signoffAction() {"Logout"}
    }
    action signoffAction() { logout(); return root(); }
  }
  
  define manageContainer( title : String ) {
    gridRow { gridCol(12){
      panel(title) {
        elements
      }
    }
  }}
  define manageContainerNested( title : String ) {
    gridRow { gridCol(12){
      wellSmall {
        <h5> output(title) </h5> 
        elements
      }
    } }
  }