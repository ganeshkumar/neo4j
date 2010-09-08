$LOAD_PATH.unshift File.join(File.dirname(__FILE__))
require 'spec_helper'


describe Neo4j::NodeMixin, :type=> :integration do

  class MyNode
    include Neo4j::NodeMixin
    property :name
    property :city
  end


  before(:each) do
    puts "CREATE INDEX"
    MyNode.index(:city)  # TODO
  end

  after(:each) do
    puts "REMOVE INDEX"
    MyNode.rm_index(:city)     # TODO
  end


  it "#[] and #[]= read and sets a neo4j property" do
    n = MyNode.new
    n.name = 'kalle'
    n.name.should == 'kalle'
  end


  it "Neo4j::Node.load loads the correct class" do
    n1 = MyNode.new
    n2 = Neo4j::Node.load(n1.id)
    # then
    n1.should == n2
  end

  it "#index should add an index" do
    n = MyNode.new
    n[:city] = 'malmoe'
    Neo4j::Transaction.finish
    Neo4j::Transaction.new

    MyNode.find(:city, 'malmoe').first.should == n
  end


  it "#index should keep the index in sync with the property value" do
    n = MyNode.new
    n[:city] = 'malmoe'
    Neo4j::Transaction.finish
    Neo4j::Transaction.new

    n[:city] = 'stockholm'
    Neo4j::Transaction.finish
    Neo4j::Transaction.new

    MyNode.find(:city, 'malmoe').first.should_not == n
    MyNode.find(:city, 'stockholm').first.should == n
  end

end