include "console.iol"
include "ls_jolie.iol"
include "string_utils.iol"
include "runtime.iol"
include "exec.iol"
include "file.iol"

execution{ concurrent }

/*
 * PORTS
 */
inputPort TextDocumentInput {
  Location: "local"
  Interfaces: TextDocumentInterface
}

outputPort SyntaxChecker {
  location: "local://SyntaxChecker"
  Interfaces: SyntaxCheckerInterface
}

outputPort JavaServiceInspector {
  Interfaces: InspectorInterface
}

embedded {
  Java: "lspservices.Inspector" in JavaServiceInspector
}

/*
 * DEFINITIONS
 */

define inspect
{
  scope( a ) {
    saveProgram = true
    install( default =>
                //valueToPrettyString@StringUtils( a )( s )
                println@Console( "ERROR" )()
                saveProgram = false
    )

    inspectionReq << {
      filename = uri
      source = docText
    }

    inspectProgram@JavaServiceInspector( inspectionReq )( inspectionRes )
  }

}

define printAllDocs
{
  valueToPrettyString@StringUtils( global.textDocument )( res )
  println@Console( res )()
}

define newDocument
{
  newDoc -> notification.textDocument
  uri = notification.textDocument.uri
  newDocVersion -> notification.textDocument.version
  docsInMemory -> global.textDocument
  splitReq = newDoc.text
  splitReq.regex = "\n"
  split@StringUtils( splitReq )( splitRes )
  document << splitRes
  document.uri = uri
  document.version = newDocVersion
  docText -> newDoc.text
  inspect //if we don't have a fault here, saveProgram = true

  if ( saveProgram ) {
    document.jolieProgram << inspectionRes
    undef( inpsectionRes )
  }

  keepRunning = true
  for(i = 0, i < #docsInMemory && keepRunning, i++) {
    if(docsInMemory[i].uri == uri && docsInMemory[i].version < newDocVersion) {
      docsInMemory[i] << document
      keepRunning = false
    }
  }

  if( keepRunning ) {
    docsInMemory[#docsInMemory] << document
  }
}

define searchDoc
{
  docFound = false
  docsInMemory -> global.textDocument
  for(i = 0, i<#docsInMemory && !fileFound, i++) {
    if(textDocUri == docsInMemory[i].uri) {
      docFound = true
      documentFoundIndex = i
    }
  }
}


/*
  * INIT and MAIN
  *
  */
init {
  println@Console( "txtDoc running" )()
  k -> global.keywords[#global.keywords]
  k = "include"
  k = "execution"
  K = "inputPort"
  k = "Interfaces"
  k = "global"
  k = "Protocol"
  k = "OneWay"
  k = "RequestResponse"
  k = "type"
  k = "define"
  k = "true"
  k = "false"
  k = "int"
  k = "inputPort"
  k = "outputPort"
  k = "interface"
  k = "is_defined"
  k = "undef"
  //TODO add all keywords
}

main {

  [ didOpen( notification ) ]  {
      println@Console( "didOpen received" )()
      newDocument
      doc.path = uri
      syntaxCheck@SyntaxChecker( doc )
  }

  /*
   * Messsage sent from the L.C. when saving a document
   * Type: DidSaveTextDocumentParams
   */
  [ didChange( notification ) ] {
      println@Console( "didChange received " )()
      docText -> notification.contentChanges[0].text[0]
      splitReq = docText
      splitReq.regex = "\n"
      split@StringUtils( splitReq )( document )
      uri -> notification.textDocument.uri
      newVersion -> notification.textDocument.version
      document << {
        uri = uri
        version = newVersion
      }

      //see definition on top
      inspect

      if( saveProgram ) {
        document.jolieProgram << inspectionRes
      }

      docsInMemory -> global.textDocument
      textDocUri -> document.uri
      searchDoc
      if ( docFound ) {
        if( docsInMemory[documentFoundIndex].version < document.version ) {
          docsInMemory[documentFoundIndex] << document
        }
      } else {
        //should never enter here
        docsInMemory[#docsInMemory] << document
      }
  }

  [ willSave( notification ) ] {
    //never received a willSave message though
    global.textDocument = notification.textDocument
    println@Console( "willSave received" )()
  }

  /*
   * Messsage sent from the L.C. when saving a document
   * Type: DidSaveTextDocumentParams
   */
  [ didSave( notification ) ] {
      println@Console( "File changed " + notification.textDocument.uri )()
      doc.path = notification.textDocument.uri
      syntaxCheck@SyntaxChecker( doc )
  }

  /*
   * Message sent from the L.C. when closing a doc
   * Type: DidCloseTextDocumentParams
   */
  [ didClose( notification ) ] {
      println@Console( "didClose received" )()
      uri = notification.textDocument.uri
      docsInMemory -> global.textDocument
      keepRunning = true
      for( i = 0, i < #docsInMemory && keepRunning, i++ ) {
        if( docsInMemory[i].uri == uri ) {
          undef( docsInMemory[i] )
          keepRunning = false
        }
      }
  }

  /*
    * RR sent sent from the client when requesting a completion
    * @Request: CompetionParams
    * @Response: CompletionResult
    */
  [ completion( completionParams )( completionRes ) {

      reqSnippet = "( ${1:requestVar} )"
      resSnippet = ""
      completionRes << {
        isIncomplete = false
      }
      valueToPrettyString@StringUtils( completionParams )( str )
      println@Console( str )()
      txtDocId -> completionParams.textDocument
      position -> completionParams.position

      if ( is_defined( completionParams.context ) ) {
        context -> completionParams.context
      }

      textDocUri -> txtDocId.uri
      //see definitions on top
      searchDoc

      if ( docFound ) {
        document -> global.textDocument[documentFoundIndex]
        //valueToPrettyString@StringUtils( document )( s )
      } //TODO else

      if ( is_defined( context.triggerCharacter ) ) {
        triggerChar -> context.triggerCharacter
        program -> document.jolieProgram
        op = document.result[position.line]
        trim@StringUtils( op )( operationName )
        portFound = false

        for ( port in program.port ) {

          if ( port.isOutput && is_defined( port.interface ) ) {
            for( iFace in port.interface ) {

              if ( is_defined( iFace.operation ) ) {
                for( op in iFace.operation ) {

                  if ( op.name == operationName ) {
                    //build the snippet
                    if ( is_defined( op.responseType ) ) {
                      //is a reqRes operation

                      if ( is_defined( op.requestType.name ) ) {
                        reqVar = op.requestType.name
                      } else {
                        reqVar = "requestVar"
                      }

                      if ( is_defined( op.responseType.name ) ) {
                        resVar = op.responseType.name
                      } else {
                        resVar = "responseVar"
                      }
                      snippet = "( ${1:" + reqVar + "} )( ${2:" + resVar + "} )"
                    } else {
                      //is a OneWay operation
                      if ( is_defined( op.requestType.name ) ) {
                        notificationVar = op.requestType.name
                      } else {
                        notificationVar = "notification"
                      }
                      snippet = "( ${1:" + notificationVar + "} )"
                    }
                    //build the completionItem
                    portFound = true
                    completionRes << {
                      items[#completionRes.items] << {
                        label = port.name
                        kind = 7
                        insertText = port.name + snippet
                        insertTextFormat = 2 //snippet
                      }
                    }
                  }
                }
              }
            }
          }
        }
      } //TODO triggerKind == 1 and == 0

      if ( !foundPort ) {
        completionRes.items = void
      }

      valueToPrettyString@StringUtils( completionRes )( s )
      println@Console( s )()
      println@Console( "Sending completion Item to the client" )()
  } ]

  [ hover( hoverReq )( hoverResp ) {
      println@Console( "hover req received.." )()
      //TODO
  } ]
}
