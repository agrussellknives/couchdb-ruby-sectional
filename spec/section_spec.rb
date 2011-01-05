#class Test < SectionalApp
#@rewrites = CouchRest.new('http://127.0.0.1')['app']['rewrites']
#@couchusers = CouchRest.new('http://127.0.0.1')['users']
#
#commands do
#  on _! do |url,opts|
#    commands = parse @couch.get(url)
#
#    on :product do |p_num|
#     
#      context do
#        @product_no = p_num
#      end
#      
#      switch_state Product do
#        on :order do |qty|
#          switch_state Cart do
#            on do
#              add_qty qty, of: @product_no
#            end
#          end
#        end
#
#        render sub_components
#      end
#
#    on :category do |p_num|
#      context do
#        @category_no = c_num
#      end
#
#      switch_state Category do
#        render sub_components
#      end
#    end
#
#    on :checkout do
#      switch_state Checkout do
#        @checkout = Checkout << :render_stage_1
#        answer @checkout do
#          on do |user,pass|
#            if @couchusers.get(user).pass != pass
#              answer @checkout & problem
#            else
#              @checkout = Checkout << :render_stage_2
#              answer @checkout do
#                on :back do
#                  send :checkout, Test
#                end
#                on do |checkout_struct|
#                  # do things to move the checkout along
#                  answer @checkouut
#                end
#              end
#            end
#          end
#        end
#      end
#    end
#  end
#end
#

#class ContactList < Section
#  class Contact < Section
#    template do 
#    <<-HTML
#      <h5 class="name">
#        <a href="{{me}}/mail">{{name}}</a>
#        <span class="actions">
#          <a href="{{me}}/delete">delete</a>
#          <a href="{{me}}/edit">edit</a>
#          <a href="{{me}}/view">view</a>
#        </span> 
#      </h5>
#    HTML
#  end
# 
#  template do
#    <<-HTML
#      <ul class="contact_list">
#        {{.contact}
#      </ul>
#    HTML
#  end
#
#  commands do
#    answer contact_list do
#      on do |contact|
#        switch_state Contact[contact]
#          on :mail do
#            switch_state MailFormDialog  
#          on :delete do
#            answer SystemConfirmDialog do
#              on :yes { return }
#              on :no { answer }
#          on :edit
#            answer ContactEdit[contact] 
#          on :save
#          on :cancel
#            answer SystemConfirmDialog do
#              on :yes { answer }
#              on :no { return }
#            end
#          on :view
#            return contact
#        end
#      end
#    end
#  end
#end



describe "section should be able to draw themselves" do
  pending
end
