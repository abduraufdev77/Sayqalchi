package uz.sayqalchi.core;
public final class Engine {
 public static final class Result {
  public final TextTools.Tool tool;public final String text,details,source,summary;
  public Result(TextTools.Tool tool,String text,String details,String source,String summary){this.tool=tool;this.text=text;this.details=details;this.source=source;this.summary=summary;}
  public boolean canReplace(){return tool!=TextTools.Tool.IZOHCHI&&!text.isEmpty();}
 }
 private final WritingServices services;
 public Engine(){this(new WritingServices());}public Engine(WritingServices services){this.services=services;}
 public Result process(TextTools.Tool tool,String input,int start,int end,String source,String target,WritingServices.Options options,WritingServices.Cancel cancel)throws Exception {
  cancel.check();if(input.trim().isEmpty())throw new IllegalArgumentException("Open a draft or enter text first.");
  if(input.length()>200000)throw new IllegalArgumentException("This editor is too long. Select a smaller passage in the Playground.");
  switch(tool){
   case FORMAT:{String text=TextTools.format(input);return new Result(tool,text,text,"","Entire draft");}
   case TRANSLATE:{String text=services.translate(input,source,target,options,cancel);return new Result(tool,text,text,"",source+" → "+target);}
   case IZOHCHI:{WritingServices.Entry entry=services.lookup(TextTools.dictionaryQuery(input,start,end),cancel);return new Result(tool,entry.render(false),entry.render(true),entry.source,"Izoh.uz");}
   default:{String text=TextTools.clean(input);return new Result(tool,text,text,"",TextTools.statistics(input));}
  }
 }
}
